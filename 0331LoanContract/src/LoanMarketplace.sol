// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title 贷款市场平台
 * @dev 实现ETH和多种代币的存款和贷款功能，采用固定利率和抵押贷款
 */
contract LoanMarketplace is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // 平台费率（以基点表示，1% = 100）
    uint256 public platformFeeRate = 50; // 0.5%

    // 最低抵押率（以百分比表示）
    uint256 public minimumCollateralRatio = 150; // 150%

    // 宽限期参数（以秒为单位）
    uint256 public gracePeriod = 3 days; // 到期后3天内还款利率不变

    // 清算奖励比例（以基点表示，500表示5%）
    uint256 public liquidationReward = 500;

    /**
     * @dev 存款要约结构(存款挂单)
     * @param depositor 存款人地址
     * @param tokenAddress 存款代币地址（0x0表示ETH）
     * @param amount 存款金额
     * @param interestRate 年化利率（以基点表示）
     * @param duration 存款期限（以秒为单位）
     * @param timestamp 创建时间戳
     * @param active 是否活跃
     */
    struct DepositOffer {
        address depositor;
        address tokenAddress; // 0x0 表示ETH
        uint256 amount;
        uint256 interestRate; // 年化利率（以基点表示）
        uint256 duration; // 以秒为单位
        uint256 timestamp;
        bool active;
    }

    /**
     * @dev 贷款要约结构(贷款挂单)
     * @param borrower 借款人地址
     * @param loanTokenAddress 借入代币地址
     * @param loanAmount 借入金额
     * @param collateralTokenAddress 抵押代币地址
     * @param collateralAmount 抵押金额
     * @param interestRate 年化利率（以基点表示）
     * @param duration 贷款期限（以秒为单位）
     * @param timestamp 创建时间戳
     * @param active 是否活跃
     */
    struct LoanOffer {
        address borrower;
        address loanTokenAddress; // 想要借的代币
        uint256 loanAmount;
        address collateralTokenAddress; // 抵押的代币
        uint256 collateralAmount;
        uint256 interestRate; // 年化利率（以基点表示）
        uint256 duration; // 以秒为单位
        uint256 timestamp;
        bool active;
    }

    /**
     * @dev 活跃贷款结构(已借出的贷款)
     * @param lender 贷款人地址
     * @param borrower 借款人地址
     * @param loanTokenAddress 借入代币地址
     * @param loanAmount 借入金额
     * @param collateralTokenAddress 抵押代币地址
     * @param collateralAmount 抵押金额
     * @param interestRate 年化利率（以基点表示）
     * @param startTime 贷款开始时间
     * @param endTime 贷款结束时间
     * @param repaid 是否已还款
     * @param liquidated 是否已清算
     */
    struct ActiveLoan {
        address lender;
        address borrower;
        address loanTokenAddress;
        uint256 loanAmount;
        address collateralTokenAddress;
        uint256 collateralAmount;
        uint256 interestRate;
        uint256 startTime;
        uint256 endTime;
        bool repaid;
        bool liquidated;
    }

    // 存储所有存款要约
    DepositOffer[] public depositOffers;

    // 存储所有贷款要约
    LoanOffer[] public loanOffers;

    // 存储所有活跃贷款
    ActiveLoan[] public activeLoans;

    // 价格预言机映射 (token地址 => 预言机地址)
    mapping(address => address) public priceFeeds;

    // 事件
    /**
     * @dev 存款要约创建事件
     * @param offerId 要约ID
     * @param depositor 存款人地址
     * @param tokenAddress 存款代币地址
     * @param amount 存款金额
     * @param interestRate 年化利率
     * @param duration 存款期限
     */
    event DepositOfferCreated(
        uint256 indexed offerId,
        address indexed depositor,
        address tokenAddress,
        uint256 amount,
        uint256 interestRate,
        uint256 duration
    );

    /**
     * @dev 存款要约取消事件
     * @param offerId 要约ID
     */
    event DepositOfferCancelled(uint256 indexed offerId);

    /**
     * @dev 贷款要约创建事件
     * @param offerId 要约ID
     * @param borrower 借款人地址
     * @param loanTokenAddress 借入代币地址
     * @param loanAmount 借入金额
     * @param collateralTokenAddress 抵押代币地址
     * @param collateralAmount 抵押金额
     * @param interestRate 年化利率
     * @param duration 贷款期限
     */
    event LoanOfferCreated(
        uint256 indexed offerId,
        address indexed borrower,
        address loanTokenAddress,
        uint256 loanAmount,
        address collateralTokenAddress,
        uint256 collateralAmount,
        uint256 interestRate,
        uint256 duration
    );

    /**
     * @dev 贷款要约取消事件
     * @param offerId 要约ID
     */
    event LoanOfferCancelled(uint256 indexed offerId);

    /**
     * @dev 贷款创建事件
     * @param loanId 贷款ID
     * @param lender 贷款人地址
     * @param borrower 借款人地址
     * @param loanTokenAddress 借入代币地址
     * @param loanAmount 借入金额
     * @param collateralTokenAddress 抵押代币地址
     * @param collateralAmount 抵押金额
     * @param interestRate 年化利率
     * @param duration 贷款期限
     */
    event LoanCreated(
        uint256 indexed loanId,
        address indexed lender,
        address indexed borrower,
        address loanTokenAddress,
        uint256 loanAmount,
        address collateralTokenAddress,
        uint256 collateralAmount,
        uint256 interestRate,
        uint256 duration
    );

    /**
     * @dev 贷款还款事件
     * @param loanId 贷款ID
     * @param repayAmount 还款金额
     */
    event LoanRepaid(uint256 indexed loanId, uint256 repayAmount);

    /**
     * @dev 贷款清算事件
     * @param loanId 贷款ID
     */
    event LoanLiquidated(uint256 indexed loanId);

    /**
     * @dev 合约构造函数
     * @param _owner 合约所有者地址
     */
    constructor(address _owner) Ownable(_owner) {}

    /**
     * @dev 设置代币价格预言机
     * @param tokenAddress 代币地址
     * @param priceFeedAddress 价格预言机地址
     */
    function setPriceFeed(address tokenAddress, address priceFeedAddress) external onlyOwner {
        priceFeeds[tokenAddress] = priceFeedAddress;
    }

    /**
     * @dev 设置平台费率
     * @param _feeRate 费率（以基点表示）
     */
    function setPlatformFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= 500, "Fee rate too high"); // 最高5%
        platformFeeRate = _feeRate;
    }

    /**
     * @dev 设置最低抵押率
     * @param _ratio 抵押率（以百分比表示）
     */
    function setMinimumCollateralRatio(uint256 _ratio) external onlyOwner {
        require(_ratio >= 110, "Collateral ratio too low");
        minimumCollateralRatio = _ratio;
    }

    /**
     * @dev 设置宽限期
     * @param _period 宽限期（以秒为单位）
     */
    function setGracePeriod(uint256 _period) external onlyOwner {
        gracePeriod = _period;
    }

    /**
     * @dev 设置清算奖励比例
     * @param _reward 奖励比例（以基点表示）
     */
    function setLiquidationReward(uint256 _reward) external onlyOwner {
        require(_reward <= 1000, "Reward too high"); // 最高10%
        liquidationReward = _reward;
    }

    /**
     * @dev 创建存款要约
     * @param tokenAddress 存款代币地址（0x0表示ETH）
     * @param amount 存款金额
     * @param interestRate 年化利率（以基点表示）
     * @param duration 存款期限（以秒为单位）
     */
    function createDepositOffer(address tokenAddress, uint256 amount, uint256 interestRate, uint256 duration)
        external
        payable
        nonReentrant
    {
        require(amount > 0, "Amount must be greater than 0");
        require(duration > 0, "Duration must be greater than 0");
        require(interestRate > 0, "Interest rate must be greater than 0");

        if (tokenAddress == address(0)) {
            // ETH存款
            require(msg.value == amount, "Sent ETH amount does not match specified amount");
        } else {
            // ERC20存款
            IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        }

        depositOffers.push(
            DepositOffer({
                depositor: msg.sender,
                tokenAddress: tokenAddress,
                amount: amount,
                interestRate: interestRate,
                duration: duration,
                timestamp: block.timestamp,
                active: true
            })
        );

        emit DepositOfferCreated(depositOffers.length - 1, msg.sender, tokenAddress, amount, interestRate, duration);
    }

    /**
     * @dev 取消存款要约
     * @param offerId 要约ID
     */
    function cancelDepositOffer(uint256 offerId) external nonReentrant {
        require(offerId < depositOffers.length, "Invalid offer ID");
        DepositOffer storage offer = depositOffers[offerId];
        require(offer.depositor == msg.sender, "Not the depositor");
        require(offer.active, "Offer not active");

        offer.active = false;

        // 返还资金
        if (offer.tokenAddress == address(0)) {
            // ETH返还
            (bool success,) = payable(msg.sender).call{value: offer.amount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20返还
            IERC20(offer.tokenAddress).safeTransfer(msg.sender, offer.amount);
        }

        emit DepositOfferCancelled(offerId);
    }

    /**
     * @dev 创建贷款要约
     * @param loanTokenAddress 借入代币地址
     * @param loanAmount 借入金额
     * @param collateralTokenAddress 抵押代币地址
     * @param collateralAmount 抵押金额
     * @param interestRate 年化利率（以基点表示）
     * @param duration 贷款期限（以秒为单位）
     */
    function createLoanOffer(
        address loanTokenAddress,
        uint256 loanAmount,
        address collateralTokenAddress,
        uint256 collateralAmount,
        uint256 interestRate,
        uint256 duration
    ) external payable nonReentrant {
        require(loanAmount > 0, "Loan amount must be greater than 0");
        require(collateralAmount > 0, "Collateral amount must be greater than 0");
        require(duration > 0, "Duration must be greater than 0");
        require(interestRate > 0, "Interest rate must be greater than 0");
        require(loanTokenAddress != collateralTokenAddress, "Loan and collateral tokens must be different");

        // 检查抵押率是否满足要求
        require(
            getCollateralRatio(collateralTokenAddress, collateralAmount, loanTokenAddress, loanAmount)
                >= minimumCollateralRatio,
            "Insufficient collateral ratio"
        );

        if (collateralTokenAddress == address(0)) {
            // ETH抵押
            require(msg.value == collateralAmount, "Sent ETH amount does not match specified collateral amount");
        } else {
            // ERC20抵押
            IERC20(collateralTokenAddress).safeTransferFrom(msg.sender, address(this), collateralAmount);
        }

        loanOffers.push(
            LoanOffer({
                borrower: msg.sender,
                loanTokenAddress: loanTokenAddress,
                loanAmount: loanAmount,
                collateralTokenAddress: collateralTokenAddress,
                collateralAmount: collateralAmount,
                interestRate: interestRate,
                duration: duration,
                timestamp: block.timestamp,
                active: true
            })
        );

        emit LoanOfferCreated(
            loanOffers.length - 1,
            msg.sender,
            loanTokenAddress,
            loanAmount,
            collateralTokenAddress,
            collateralAmount,
            interestRate,
            duration
        );
    }

    /**
     * @dev 取消贷款要约
     * @param offerId 要约ID
     */
    function cancelLoanOffer(uint256 offerId) external nonReentrant {
        require(offerId < loanOffers.length, "Invalid offer ID");
        LoanOffer storage offer = loanOffers[offerId];
        require(offer.borrower == msg.sender, "Not the borrower");
        require(offer.active, "Offer not active");

        offer.active = false;

        // 返还抵押品
        if (offer.collateralTokenAddress == address(0)) {
            // ETH返还
            (bool success,) = payable(msg.sender).call{value: offer.collateralAmount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20返还
            IERC20(offer.collateralTokenAddress).safeTransfer(msg.sender, offer.collateralAmount);
        }

        emit LoanOfferCancelled(offerId);
    }

    /**
     * @dev 接受存款要约（借款人调用）
     * @param offerId 要约ID
     * @param collateralTokenAddress 抵押代币地址
     * @param collateralAmount 抵押金额
     */
    function acceptDepositOffer(uint256 offerId, address collateralTokenAddress, uint256 collateralAmount)
        external
        payable
        nonReentrant
    {
        require(offerId < depositOffers.length, "Invalid offer ID");
        DepositOffer storage offer = depositOffers[offerId];
        require(offer.active, "Offer not active");

        // 检查抵押率是否满足要求
        require(
            getCollateralRatio(collateralTokenAddress, collateralAmount, offer.tokenAddress, offer.amount)
                >= minimumCollateralRatio,
            "Insufficient collateral ratio"
        );

        // 处理抵押品
        if (collateralTokenAddress == address(0)) {
            // ETH抵押
            require(msg.value == collateralAmount, "Sent ETH amount does not match specified collateral amount");
        } else {
            // ERC20抵押
            IERC20(collateralTokenAddress).safeTransferFrom(msg.sender, address(this), collateralAmount);
        }

        // 计算平台费用
        uint256 platformFee = (offer.amount * platformFeeRate) / 10000;
        uint256 loanAmount = offer.amount - platformFee;

        // 将贷款金额转给借款人
        if (offer.tokenAddress == address(0)) {
            // ETH贷款
            (bool success,) = payable(msg.sender).call{value: loanAmount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20贷款
            IERC20(offer.tokenAddress).safeTransfer(msg.sender, loanAmount);
        }

        // 创建活跃贷款记录
        activeLoans.push(
            ActiveLoan({
                lender: offer.depositor,
                borrower: msg.sender,
                loanTokenAddress: offer.tokenAddress,
                loanAmount: offer.amount,
                collateralTokenAddress: collateralTokenAddress,
                collateralAmount: collateralAmount,
                interestRate: offer.interestRate,
                startTime: block.timestamp,
                endTime: block.timestamp + offer.duration,
                repaid: false,
                liquidated: false
            })
        );

        // 标记存款要约为非活跃
        offer.active = false;

        emit LoanCreated(
            activeLoans.length - 1,
            offer.depositor,
            msg.sender,
            offer.tokenAddress,
            offer.amount,
            collateralTokenAddress,
            collateralAmount,
            offer.interestRate,
            offer.duration
        );
    }

    /**
     * @dev 接受贷款要约（存款人调用）
     * @param offerId 要约ID
     */
    function acceptLoanOffer(uint256 offerId) external payable nonReentrant {
        require(offerId < loanOffers.length, "Invalid offer ID");
        LoanOffer storage offer = loanOffers[offerId];
        require(offer.active, "Offer not active");

        // 处理贷款资金
        uint256 platformFee = (offer.loanAmount * platformFeeRate) / 10000;
        uint256 requiredAmount = offer.loanAmount + platformFee;

        if (offer.loanTokenAddress == address(0)) {
            // ETH贷款
            require(msg.value == requiredAmount, "Sent ETH amount does not match required amount");
        } else {
            // ERC20贷款
            IERC20(offer.loanTokenAddress).safeTransferFrom(msg.sender, address(this), requiredAmount);
        }

        // 将贷款金额转给借款人
        if (offer.loanTokenAddress == address(0)) {
            // ETH贷款
            (bool success,) = payable(offer.borrower).call{value: offer.loanAmount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20贷款
            IERC20(offer.loanTokenAddress).safeTransfer(offer.borrower, offer.loanAmount);
        }

        // 创建活跃贷款记录
        activeLoans.push(
            ActiveLoan({
                lender: msg.sender,
                borrower: offer.borrower,
                loanTokenAddress: offer.loanTokenAddress,
                loanAmount: offer.loanAmount,
                collateralTokenAddress: offer.collateralTokenAddress,
                collateralAmount: offer.collateralAmount,
                interestRate: offer.interestRate,
                startTime: block.timestamp,
                endTime: block.timestamp + offer.duration,
                repaid: false,
                liquidated: false
            })
        );

        // 标记贷款要约为非活跃
        offer.active = false;

        emit LoanCreated(
            activeLoans.length - 1,
            msg.sender,
            offer.borrower,
            offer.loanTokenAddress,
            offer.loanAmount,
            offer.collateralTokenAddress,
            offer.collateralAmount,
            offer.interestRate,
            offer.duration
        );
    }

    /**
     * @dev 还款
     * @param loanId 贷款ID
     */
    function repayLoan(uint256 loanId) external payable nonReentrant {
        require(loanId < activeLoans.length, "Invalid loan ID");
        ActiveLoan storage loan = activeLoans[loanId];
        require(loan.borrower == msg.sender, "Not the borrower");
        require(!loan.repaid, "Loan already repaid");
        require(!loan.liquidated, "Loan already liquidated");

        // 计算基础利息
        uint256 timeElapsed =
            block.timestamp > loan.endTime ? loan.endTime - loan.startTime : block.timestamp - loan.startTime;
        uint256 baseInterest = (loan.loanAmount * loan.interestRate * timeElapsed) / (10000 * 365 days);

        uint256 totalInterest;

        // 判断是提前还款、正常还款还是逾期还款
        if (block.timestamp < loan.endTime) {
            // 提前还款，利率翻倍
            totalInterest = baseInterest * 2;
        } else if (block.timestamp <= loan.endTime + gracePeriod) {
            // 正常还款（在宽限期内）
            totalInterest = baseInterest;
        } else {
            // 逾期还款，利率翻倍
            uint256 overdueDays = (block.timestamp - loan.endTime - gracePeriod) / 1 days;
            if (overdueDays > 0) {
                uint256 overdueInterest = (loan.loanAmount * loan.interestRate * overdueDays * 2) / (10000 * 365);
                totalInterest = baseInterest + overdueInterest;
            } else {
                totalInterest = baseInterest;
            }
        }

        uint256 totalRepayment = loan.loanAmount + totalInterest;

        // 处理还款
        if (loan.loanTokenAddress == address(0)) {
            // ETH还款
            require(msg.value == totalRepayment, "Incorrect ETH amount sent");

            // 将本金和利息转给贷款人
            (bool success,) = payable(loan.lender).call{value: totalRepayment}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20还款
            IERC20(loan.loanTokenAddress).safeTransferFrom(msg.sender, loan.lender, totalRepayment);
        }

        // 返还抵押品
        if (loan.collateralTokenAddress == address(0)) {
            // ETH抵押品
            (bool success,) = payable(msg.sender).call{value: loan.collateralAmount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20抵押品
            IERC20(loan.collateralTokenAddress).safeTransfer(msg.sender, loan.collateralAmount);
        }

        // 标记贷款为已还款
        loan.repaid = true;

        emit LoanRepaid(loanId, totalRepayment);
    }

    /**
     * @dev 清算不健康的贷款
     * @param loanId 贷款ID
     */
    function liquidateLoan(uint256 loanId) external nonReentrant {
        require(loanId < activeLoans.length, "Invalid loan ID");
        ActiveLoan storage loan = activeLoans[loanId];
        require(!loan.repaid, "Loan already repaid");
        require(!loan.liquidated, "Loan already liquidated");

        // 检查是否可以清算（抵押率低于最低要求或贷款已过期）
        bool canLiquidate = block.timestamp > loan.endTime;
        if (!canLiquidate) {
            uint256 currentRatio = getCollateralRatio(
                loan.collateralTokenAddress, loan.collateralAmount, loan.loanTokenAddress, loan.loanAmount
            );
            canLiquidate = currentRatio < minimumCollateralRatio;
        }

        require(canLiquidate, "Loan cannot be liquidated");

        // 计算清算人奖励
        uint256 rewardAmount = (loan.collateralAmount * liquidationReward) / 10000;
        uint256 lenderAmount = loan.collateralAmount - rewardAmount;

        // 将抵押品分配给贷款人和清算人
        if (loan.collateralTokenAddress == address(0)) {
            // ETH抵押品
            // 发送给贷款人
            (bool successLender,) = payable(loan.lender).call{value: lenderAmount}("");
            require(successLender, "ETH transfer to lender failed");

            // 发送给清算人
            (bool successLiquidator,) = payable(msg.sender).call{value: rewardAmount}("");
            require(successLiquidator, "ETH transfer to liquidator failed");
        } else {
            // ERC20抵押品
            // 发送给贷款人
            IERC20(loan.collateralTokenAddress).safeTransfer(loan.lender, lenderAmount);

            // 发送给清算人
            IERC20(loan.collateralTokenAddress).safeTransfer(msg.sender, rewardAmount);
        }

        // 标记贷款为已清算
        loan.liquidated = true;

        emit LoanLiquidated(loanId);
    }

    /**
     * @dev 获取抵押率（以百分比表示）
     * @param collateralTokenAddress 抵押代币地址
     * @param collateralAmount 抵押金额
     * @param loanTokenAddress 贷款代币地址
     * @param loanAmount 贷款金额
     * @return 抵押率（百分比）
     */
    function getCollateralRatio(
        address collateralTokenAddress,
        uint256 collateralAmount,
        address loanTokenAddress,
        uint256 loanAmount
    ) public view returns (uint256) {
        // 获取抵押品价值（以USD为单位）
        uint256 collateralValueUSD = getTokenValueInUSD(collateralTokenAddress, collateralAmount);

        // 获取贷款价值（以USD为单位）
        uint256 loanValueUSD = getTokenValueInUSD(loanTokenAddress, loanAmount);

        // 计算抵押率
        if (loanValueUSD == 0) return 0;
        return (collateralValueUSD * 100) / loanValueUSD;
    }

    /**
     * @dev 获取代币价值（以USD为单位）
     * @param tokenAddress 代币地址
     * @param amount 代币数量
     * @return 美元价值
     */
    function getTokenValueInUSD(address tokenAddress, uint256 amount) public view returns (uint256) {
        if (amount == 0) return 0;

        address priceFeedAddress = priceFeeds[tokenAddress];
        require(priceFeedAddress != address(0), "Price feed not set for token");

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);

        // 获取最新价格
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");

        // 获取小数位数
        uint8 decimals = priceFeed.decimals();

        uint256 tokenDecimals;
        if (tokenAddress == address(0)) {
            tokenDecimals = 18; // ETH有18个小数位
        } else {
            try IERC20Metadata(tokenAddress).decimals() returns (uint8 _decimals) {
                tokenDecimals = _decimals;
            } catch {
                tokenDecimals = 18; // 默认为18个小数位
            }
        }

        // 计算总小数位与目标小数位（18）的差值
        uint256 totalDecimals = tokenDecimals + uint256(decimals);
        uint256 result = amount * uint256(price);

        if (totalDecimals >= 18) {
            return result / (10 ** (totalDecimals - 18));
        } else {
            return result * (10 ** (18 - totalDecimals));
        }
    }

    /**
     * @dev 获取指定贷款的当前还款金额
     * @param loanId 贷款ID
     * @return 当前还款金额
     */
    function getRepaymentAmount(uint256 loanId) public view returns (uint256) {
        require(loanId < activeLoans.length, "Invalid loan ID");
        ActiveLoan storage loan = activeLoans[loanId];
        require(!loan.repaid, "Loan already repaid");
        require(!loan.liquidated, "Loan already liquidated");

        uint256 timeElapsed =
            block.timestamp > loan.endTime ? loan.endTime - loan.startTime : block.timestamp - loan.startTime;
        uint256 baseInterest = (loan.loanAmount * loan.interestRate * timeElapsed) / (10000 * 365 days);

        uint256 totalInterest;
        if (block.timestamp < loan.endTime) {
            totalInterest = baseInterest * 2; // 提前还款，利息翻倍
        } else if (block.timestamp <= loan.endTime + gracePeriod) {
            totalInterest = baseInterest; // 宽限期内，正常利息
        } else {
            uint256 overdueDays = (block.timestamp - loan.endTime - gracePeriod) / 1 days;
            if (overdueDays > 0) {
                uint256 overdueInterest = (loan.loanAmount * loan.interestRate * overdueDays * 2) / (10000 * 365);
                totalInterest = baseInterest + overdueInterest; // 逾期利息
            } else {
                totalInterest = baseInterest;
            }
        }

        return loan.loanAmount + totalInterest;
    }

    /**
     * @dev 提取平台费用（仅限所有者）
     * @param tokenAddress 代币地址
     * @param amount 提取金额
     */
    function withdrawPlatformFees(address tokenAddress, uint256 amount) external onlyOwner {
        if (tokenAddress == address(0)) {
            // 提取ETH
            (bool success,) = payable(owner()).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // 提取ERC20
            IERC20(tokenAddress).safeTransfer(owner(), amount);
        }
    }

    /**
     * @dev 接收ETH
     */
    receive() external payable {}
}

/**
 * @dev ERC20元数据接口，用于获取代币小数位数
 */
interface IERC20Metadata is IERC20 {
    function decimals() external view returns (uint8);
}
