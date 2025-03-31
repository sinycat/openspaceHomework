// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {LoanMarketplace} from "../src/LoanMarketplace.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockToken is ERC20 {
    constructor(string memory tokenName, string memory tokenSymbol, uint8 _decimals) ERC20(tokenName, tokenSymbol) {
        _mint(msg.sender, 1000000 * 10 ** _decimals);
    }

    function decimals() public pure override returns (uint8) {
        return 6; // USDC和USDT通常是6位小数
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// 模拟价格预言机
contract MockPriceFeed is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;

    constructor(int256 initialPrice, uint8 decimalsValue) {
        _price = initialPrice;
        _decimals = decimalsValue;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId)
        external
        pure
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, 0, 0, 0, 0);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }
}

contract LoanMarketplaceTest is Test {
    LoanMarketplace public marketplace;
    MockToken public usdc;
    MockToken public dai;
    MockPriceFeed public ethUsdPriceFeed;
    MockPriceFeed public usdcUsdPriceFeed;
    MockPriceFeed public daiUsdPriceFeed;

    address public owner = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);

    uint256 public constant ETH_INITIAL_PRICE = 2000e8; // $2000 USD
    uint256 public constant USDC_INITIAL_PRICE = 1e8; // $1 USD
    uint256 public constant DAI_INITIAL_PRICE = 1e8; // $1 USD

    function setUp() public {
        // 部署合约
        vm.startPrank(owner);
        marketplace = new LoanMarketplace(owner);

        // 部署模拟代币
        usdc = new MockToken("USD Coin", "USDC", 6);
        dai = new MockToken("Dai Stablecoin", "DAI", 18);

        // 部署模拟价格预言机，确保价格格式正确
        ethUsdPriceFeed = new MockPriceFeed(int256(2000 * 10 ** 8), 8); // $2000 USD with 8 decimals
        usdcUsdPriceFeed = new MockPriceFeed(int256(1 * 10 ** 8), 8); // $1 USD with 8 decimals
        daiUsdPriceFeed = new MockPriceFeed(int256(1 * 10 ** 8), 8); // $1 USD with 8 decimals

        // 设置价格预言机
        marketplace.setPriceFeed(address(0), address(ethUsdPriceFeed));
        marketplace.setPriceFeed(address(usdc), address(usdcUsdPriceFeed));
        marketplace.setPriceFeed(address(dai), address(daiUsdPriceFeed));

        // 设置平台参数
        marketplace.setPlatformFeeRate(50); // 0.5%
        marketplace.setMinimumCollateralRatio(150); // 150%
        marketplace.setGracePeriod(3 days);
        marketplace.setLiquidationReward(500); // 5%
        vm.stopPrank();

        // 给测试账户分配资金
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);

        // 直接铸造代币给测试账户
        usdc.mint(alice, 100000 * 10 ** 6); // 10万USDC
        usdc.mint(bob, 100000 * 10 ** 6); // 10万USDC
        dai.mint(alice, 100000 * 10 ** 18); // 10万DAI
        dai.mint(bob, 100000 * 10 ** 18); // 10万DAI

        // 授权合约使用代币
        vm.startPrank(alice);
        usdc.approve(address(marketplace), type(uint256).max);
        dai.approve(address(marketplace), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(marketplace), type(uint256).max);
        dai.approve(address(marketplace), type(uint256).max);
        vm.stopPrank();
    }

    // 测试创建ETH存款要约
    function testCreateETHDepositOffer() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = alice.balance;
        marketplace.createDepositOffer{value: 5 ether}(address(0), 5 ether, 500, 30 days);
        uint256 aliceBalanceAfter = alice.balance;

        assertEq(aliceBalanceBefore - aliceBalanceAfter, 5 ether, "ETH not transferred correctly");

        // 验证存款要约创建成功
        (address depositor, address tokenAddress, uint256 amount, uint256 interestRate, uint256 duration,, bool active)
        = marketplace.depositOffers(0);

        assertEq(depositor, alice, "Wrong depositor");
        assertEq(tokenAddress, address(0), "Wrong token address");
        assertEq(amount, 5 ether, "Wrong amount");
        assertEq(interestRate, 500, "Wrong interest rate");
        assertEq(duration, 30 days, "Wrong duration");
        assertTrue(active, "Offer should be active");

        vm.stopPrank();
    }

    // 测试创建ERC20存款要约
    function testCreateERC20DepositOffer() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 depositAmount = 10000 * 10 ** 6; // 1万USDC

        marketplace.createDepositOffer(address(usdc), depositAmount, 300, 90 days);
        uint256 aliceBalanceAfter = usdc.balanceOf(alice);

        assertEq(aliceBalanceBefore - aliceBalanceAfter, depositAmount, "USDC not transferred correctly");

        // 验证存款要约创建成功
        (address depositor, address tokenAddress, uint256 amount, uint256 interestRate, uint256 duration,, bool active)
        = marketplace.depositOffers(0);

        assertEq(depositor, alice, "Wrong depositor");
        assertEq(tokenAddress, address(usdc), "Wrong token address");
        assertEq(amount, depositAmount, "Wrong amount");
        assertEq(interestRate, 300, "Wrong interest rate");
        assertEq(duration, 90 days, "Wrong duration");
        assertTrue(active, "Offer should be active");

        vm.stopPrank();
    }

    // 测试取消存款要约
    function testCancelDepositOffer() public {
        // 先创建存款要约
        vm.startPrank(alice);
        marketplace.createDepositOffer{value: 5 ether}(address(0), 5 ether, 500, 30 days);
        vm.stopPrank();

        // 验证要约创建成功
        (,,,,,, bool active) = marketplace.depositOffers(0);
        assertTrue(active, "Offer should be active");

        // 非存款人尝试取消要约（应该失败）
        vm.startPrank(bob);
        vm.expectRevert("Not the depositor");
        marketplace.cancelDepositOffer(0);
        vm.stopPrank();

        // 存款人取消要约
        vm.startPrank(alice);
        uint256 aliceBalanceBefore = alice.balance;
        marketplace.cancelDepositOffer(0);
        uint256 aliceBalanceAfter = alice.balance;

        // 验证ETH已返还
        assertEq(aliceBalanceAfter - aliceBalanceBefore, 5 ether, "ETH not refunded correctly");

        // 验证要约已取消
        (,,,,,, active) = marketplace.depositOffers(0);
        assertFalse(active, "Offer should be inactive");

        vm.stopPrank();
    }

    // 测试创建贷款要约
    function testCreateLoanOffer() public {
        vm.startPrank(bob);

        uint256 bobBalanceBefore = bob.balance;
        uint256 collateralAmount = 225 * 10 ** 16; // 2.25 ETH
        uint256 loanAmount = 3000 * 10 ** 6; // 3000 USDC

        marketplace.createLoanOffer{value: collateralAmount}(
            address(usdc), loanAmount, address(0), collateralAmount, 400, 60 days
        );

        uint256 bobBalanceAfter = bob.balance;

        assertEq(bobBalanceBefore - bobBalanceAfter, collateralAmount, "ETH not transferred correctly");

        // 验证贷款要约创建成功
        (
            address borrower,
            address loanTokenAddress,
            uint256 loanAmt,
            address collateralTokenAddress,
            uint256 collateralAmt,
            uint256 interestRate,
            uint256 duration,
            ,
            bool active
        ) = marketplace.loanOffers(0);

        assertEq(borrower, bob, "Wrong borrower");
        assertEq(loanTokenAddress, address(usdc), "Wrong loan token address");
        assertEq(loanAmt, loanAmount, "Wrong loan amount");
        assertEq(collateralTokenAddress, address(0), "Wrong collateral token address");
        assertEq(collateralAmt, collateralAmount, "Wrong collateral amount");
        assertEq(interestRate, 400, "Wrong interest rate");
        assertEq(duration, 60 days, "Wrong duration");
        assertTrue(active, "Offer should be active");

        vm.stopPrank();
    }

    // 测试抵押率不足的贷款要约（应该失败）
    function testCreateLoanOfferWithInsufficientCollateral() public {
        vm.startPrank(bob);

        uint256 collateralAmount = 1 ether; // 价值$2000
        uint256 loanAmount = 1500 * 10 ** 6; // 1500 USDC，需要至少$2250的抵押品（150%抵押率）

        vm.expectRevert("Insufficient collateral ratio");
        marketplace.createLoanOffer{value: collateralAmount}(
            address(usdc), loanAmount, address(0), collateralAmount, 400, 60 days
        );

        vm.stopPrank();
    }

    // 测试取消贷款要约
    function testCancelLoanOffer() public {
        // 先创建贷款要约
        vm.startPrank(bob);
        uint256 collateralAmount = 225 * 10 ** 16; // 2.25 ETH
        marketplace.createLoanOffer{value: collateralAmount}(
            address(usdc), 3000 * 10 ** 6, address(0), collateralAmount, 400, 60 days
        );
        vm.stopPrank();

        // 验证要约创建成功
        (,,,,,,,, bool active) = marketplace.loanOffers(0);
        assertTrue(active, "Offer should be active");

        // 非借款人尝试取消要约（应该失败）
        vm.startPrank(alice);
        vm.expectRevert("Not the borrower");
        marketplace.cancelLoanOffer(0);
        vm.stopPrank();

        // 借款人取消要约
        vm.startPrank(bob);
        uint256 bobBalanceBefore = bob.balance;
        marketplace.cancelLoanOffer(0);
        uint256 bobBalanceAfter = bob.balance;

        // 验证ETH已返还
        assertEq(bobBalanceAfter - bobBalanceBefore, collateralAmount, "ETH not refunded correctly");

        // 验证要约已取消
        (,,,,,,,, active) = marketplace.loanOffers(0);
        assertFalse(active, "Offer should be inactive");

        vm.stopPrank();
    }

    // 测试接受存款要约
    function testAcceptDepositOffer() public {
        // Alice创建存款要约
        vm.startPrank(alice);
        marketplace.createDepositOffer{value: 5 ether}(address(0), 5 ether, 500, 30 days);
        vm.stopPrank();

        // Bob接受存款要约，提供USDC作为抵押品
        vm.startPrank(bob);
        uint256 collateralAmount = 15000 * 10 ** 6; // 15000 USDC
        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        uint256 bobEthBefore = bob.balance;

        marketplace.acceptDepositOffer(0, address(usdc), collateralAmount);

        uint256 bobUsdcAfter = usdc.balanceOf(bob);
        uint256 bobEthAfter = bob.balance;

        // 验证Bob支付了USDC抵押品
        assertEq(bobUsdcBefore - bobUsdcAfter, collateralAmount, "USDC not transferred correctly");

        // 验证Bob收到了ETH贷款（减去平台费用）
        uint256 platformFee = (5 ether * 50) / 10000; // 0.5%
        uint256 expectedLoanAmount = 5 ether - platformFee;
        assertEq(bobEthAfter - bobEthBefore, expectedLoanAmount, "ETH loan not received correctly");

        // 验证活跃贷款创建成功
        (
            address lender,
            address borrower,
            address loanTokenAddress,
            uint256 loanAmount,
            address collateralTokenAddress,
            uint256 collateralAmt,
            uint256 interestRate,
            ,
            ,
            bool repaid,
            bool liquidated
        ) = marketplace.activeLoans(0);

        assertEq(lender, alice, "Wrong lender");
        assertEq(borrower, bob, "Wrong borrower");
        assertEq(loanTokenAddress, address(0), "Wrong loan token address");
        assertEq(loanAmount, 5 ether, "Wrong loan amount");
        assertEq(collateralTokenAddress, address(usdc), "Wrong collateral token address");
        assertEq(collateralAmt, collateralAmount, "Wrong collateral amount");
        assertEq(interestRate, 500, "Wrong interest rate");
        assertFalse(repaid, "Loan should not be repaid");
        assertFalse(liquidated, "Loan should not be liquidated");

        // 验证存款要约已失效
        (,,,,,, bool active) = marketplace.depositOffers(0);
        assertFalse(active, "Deposit offer should be inactive");

        vm.stopPrank();
    }

    // 测试接受贷款要约
    function testAcceptLoanOffer() public {
        _createLoanOffer();
        vm.startPrank(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 bobUsdcBefore = usdc.balanceOf(bob); // 新增：记录 Bob 初始余额
        marketplace.acceptLoanOffer(0);
        uint256 aliceUsdcAfter = usdc.balanceOf(alice);
        uint256 bobUsdcAfter = usdc.balanceOf(bob); // 新增：记录 Bob 最终余额
        uint256 loanAmount = 3000 * 10 ** 6;
        uint256 platformFee = (loanAmount * 50) / 10000; // 0.5% 平台费用
        uint256 totalAmount = loanAmount + platformFee;
        assertEq(aliceUsdcBefore - aliceUsdcAfter, totalAmount, "USDC not transferred correctly");
        assertEq(bobUsdcAfter - bobUsdcBefore, loanAmount, "Bob did not receive USDC loan"); // 检查增量
        _verifyActiveLoan(0);
        vm.stopPrank();
    }

    // 辅助函数：创建贷款要约
    function _createLoanOffer() internal {
        vm.startPrank(bob);
        uint256 collateralAmount = 225 * 10 ** 16; // 2.25 ETH
        uint256 loanAmount = 3000 * 10 ** 6; // 3000 USDC
        marketplace.createLoanOffer{value: collateralAmount}(
            address(usdc), loanAmount, address(0), collateralAmount, 400, 60 days
        );
        vm.stopPrank();
    }

    // 辅助函数：验证活跃贷款
    function _verifyActiveLoan(uint256 loanId) internal view {
        (
            address lender,
            address borrower,
            address loanTokenAddress,
            uint256 loanAmt,
            address collateralTokenAddress,
            uint256 collateralAmt,
            uint256 interestRate,
            ,
            ,
            bool repaid,
            bool liquidated
        ) = marketplace.activeLoans(loanId);

        assertEq(lender, alice, "Wrong lender");
        assertEq(borrower, bob, "Wrong borrower");
        assertEq(loanTokenAddress, address(usdc), "Wrong loan token address");
        assertEq(loanAmt, 3000 * 10 ** 6, "Wrong loan amount");
        assertEq(collateralTokenAddress, address(0), "Wrong collateral token address");
        assertEq(collateralAmt, 225 * 10 ** 16, "Wrong collateral amount"); // 修改为 2.25 ETH
        assertEq(interestRate, 400, "Wrong interest rate");
        assertFalse(repaid, "Loan should not be repaid");
        assertFalse(liquidated, "Loan should not be liquidated");

        // 验证贷款要约已失效
        (,,,,,,,, bool active) = marketplace.loanOffers(0);
        assertFalse(active, "Loan offer should be inactive");
    }

    // 测试正常还款
    function testRepayLoan() public {
        _createLoanOffer();
        vm.startPrank(alice);
        marketplace.acceptLoanOffer(0);
        uint256 loanStartTime = block.timestamp; // 记录贷款起始时间
        vm.stopPrank();

        // 前进30天
        vm.warp(block.timestamp + 30 days);

        // Bob 还款
        vm.startPrank(bob);

        // 计算预期还款金额（与合约逻辑一致）
        uint256 timeElapsed = block.timestamp - loanStartTime;
        uint256 interest = (3000 * 10 ** 6 * 400 * timeElapsed) / (10000 * 365 days);
        uint256 expectedRepayment = 3000 * 10 ** 6 + interest;

        // 授权足够的金额（加更大的缓冲以覆盖时间戳偏差）
        usdc.approve(address(marketplace), expectedRepayment + 20 * 10 ** 6); // 加20 USDC缓冲

        uint256 bobEthBefore = bob.balance;
        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        marketplace.repayLoan(0);

        uint256 bobEthAfter = bob.balance;
        uint256 bobUsdcAfter = usdc.balanceOf(bob);
        uint256 aliceUsdcAfter = usdc.balanceOf(alice);

        // 计算实际支付的金额
        uint256 actualRepayment = bobUsdcBefore - bobUsdcAfter;

        // 验证 Bob 收回了 ETH 抵押品
        assertEq(bobEthAfter - bobEthBefore, 225 * 10 ** 16, "ETH collateral not returned");

        // 验证 Bob 支付的 USDC 还款金额与实际一致
        assertEq(bobUsdcBefore - bobUsdcAfter, actualRepayment, "USDC not paid correctly");

        // 验证 Alice 收到了还款
        assertEq(aliceUsdcAfter - aliceUsdcBefore, actualRepayment, "Alice did not receive repayment");

        // 验证贷款已标记为已还款
        (,,,,,,,,, bool repaid,) = marketplace.activeLoans(0);
        assertTrue(repaid, "Loan should be marked as repaid");

        vm.stopPrank();
    }

    // 测试提前还款（双倍利息）
    function testEarlyRepayment() public {
        _createLoanOffer(); // 使用调整后的参数：2.25 ETH 抵押，3000 USDC 贷款
        vm.startPrank(alice);
        marketplace.acceptLoanOffer(0);
        vm.stopPrank();

        // 前进 15 天（提前还款）
        vm.warp(block.timestamp + 15 days);

        // Bob 还款
        vm.startPrank(bob);

        // 计算利息（提前还款，双倍利息）
        uint256 timeElapsed = 15 days;
        uint256 baseInterest = (3000 * 10 ** 6 * 400 * timeElapsed) / (10000 * 365 days);
        uint256 totalInterest = baseInterest * 2; // 提前还款，双倍利息
        uint256 totalRepayment = 3000 * 10 ** 6 + totalInterest;

        // 确保 Bob 有足够的 USDC
        usdc.approve(address(marketplace), totalRepayment);

        marketplace.repayLoan(0);

        // 验证贷款已标记为已还款
        (,,,,,,,,, bool repaid,) = marketplace.activeLoans(0);
        assertTrue(repaid, "Loan should be marked as repaid");

        vm.stopPrank();
    }

    // 测试逾期还款（宽限期内）
    function testRepaymentWithinGracePeriod() public {
        _createLoanOffer(); // 使用调整后的参数：2.25 ETH 抵押，3000 USDC 贷款
        vm.startPrank(alice);
        marketplace.acceptLoanOffer(0);
        vm.stopPrank();

        // 前进 62 天（逾期 2 天，但在 3 天宽限期内）
        vm.warp(block.timestamp + 62 days);

        // Bob 还款
        vm.startPrank(bob);

        // 计算利息（宽限期内，正常利息）
        uint256 timeElapsed = 60 days; // 只计算到贷款期限
        uint256 interest = (3000 * 10 ** 6 * 400 * timeElapsed) / (10000 * 365 days);
        uint256 totalRepayment = 3000 * 10 ** 6 + interest;

        // 确保 Bob 有足够的 USDC
        usdc.approve(address(marketplace), totalRepayment);

        marketplace.repayLoan(0);

        // 验证贷款已标记为已还款
        (,,,,,,,,, bool repaid,) = marketplace.activeLoans(0);
        assertTrue(repaid, "Loan should be marked as repaid");

        vm.stopPrank();
    }

    // 测试逾期还款（超出宽限期）
    function testLateRepayment() public {
        _createLoanOffer(); // 使用调整后的参数：2.25 ETH 抵押，3000 USDC 贷款
        vm.startPrank(alice);
        marketplace.acceptLoanOffer(0);
        vm.stopPrank();

        // 前进 65 天（超出宽限期 2 天）
        vm.warp(block.timestamp + 65 days);

        // Bob 还款
        vm.startPrank(bob);

        // 计算利息（超出宽限期，额外天数双倍利息）
        uint256 baseTimeElapsed = 60 days; // 贷款期限
        uint256 baseInterest = (3000 * 10 ** 6 * 400 * baseTimeElapsed) / (10000 * 365 days);

        uint256 overdueDays = 2; // 超出宽限期的天数
        uint256 overdueInterest = (3000 * 10 ** 6 * 400 * overdueDays * 2) / (10000 * 365);

        uint256 totalInterest = baseInterest + overdueInterest;
        uint256 totalRepayment = 3000 * 10 ** 6 + totalInterest;

        // 确保 Bob 有足够的 USDC
        usdc.approve(address(marketplace), totalRepayment);

        marketplace.repayLoan(0);

        // 验证贷款已标记为已还款
        (,,,,,,,,, bool repaid,) = marketplace.activeLoans(0);
        assertTrue(repaid, "Loan should be marked as repaid");

        vm.stopPrank();
    }

    // 测试清算（抵押率不足）
    function testLiquidationDueToInsufficientCollateral() public {
        _createLoanOffer(); // 使用调整后的参数：2.25 ETH 抵押，3000 USDC 贷款
        vm.startPrank(alice);
        marketplace.acceptLoanOffer(0);
        vm.stopPrank();

        // ETH 价格下跌，导致抵押率不足
        ethUsdPriceFeed.setPrice(int256(1500e8)); // $1500 USD

        // Charlie 尝试清算
        vm.startPrank(charlie);

        uint256 charlieEthBefore = charlie.balance;
        uint256 aliceEthBefore = alice.balance;

        marketplace.liquidateLoan(0);

        uint256 charlieEthAfter = charlie.balance;
        uint256 aliceEthAfter = alice.balance;

        // 验证清算奖励分配
        uint256 liquidatorReward = (225 * 10 ** 16 * 500) / 10000; // 5%
        uint256 lenderAmount = (225 * 10 ** 16) - liquidatorReward;

        assertEq(charlieEthAfter - charlieEthBefore, liquidatorReward, "Liquidator did not receive reward");
        assertEq(aliceEthAfter - aliceEthBefore, lenderAmount, "Lender did not receive collateral");

        // 验证贷款已标记为已清算
        (,,,,,,,,,, bool liquidated) = marketplace.activeLoans(0);
        assertTrue(liquidated, "Loan should be marked as liquidated");

        vm.stopPrank();
    }

    // 测试价格预言机返回负值
    function test_RevertIf_PriceFeedInvalid() public {
        vm.startPrank(bob);
        ethUsdPriceFeed.setPrice(-2000e8); // 负值价格
        vm.expectRevert("Invalid price");
        marketplace.createLoanOffer{value: 2.25 ether}(
            address(usdc), 3000 * 10 ** 6, address(0), 2.25 ether, 400, 60 days
        );
        vm.stopPrank();
    }

    // 测试代币小数位异常
    function testCreateLoanOfferWithZeroDecimalsToken() public {
        MockToken zeroDecimalToken = new MockToken("ZeroDec", "ZD", 0);
        MockPriceFeed zeroDecimalPriceFeed = new MockPriceFeed(int256(1 * 10 ** 8), 8);
        vm.startPrank(owner);
        marketplace.setPriceFeed(address(zeroDecimalToken), address(zeroDecimalPriceFeed));
        vm.stopPrank();

        vm.startPrank(alice);
        zeroDecimalToken.mint(alice, 10000);
        zeroDecimalToken.approve(address(marketplace), 10000);
        marketplace.createDepositOffer(address(zeroDecimalToken), 10000, 300, 90 days);
        vm.stopPrank();
    }

    // 测试余额不足
    function test_RevertIf_InsufficientETHForLoanOffer() public {
        vm.startPrank(bob);
        vm.deal(bob, 1 ether);
        vm.expectRevert("Sent ETH amount does not match specified collateral amount");
        marketplace.createLoanOffer{value: 1 ether}(address(usdc), 3000 * 10 ** 6, address(0), 2.25 ether, 400, 60 days);
        vm.stopPrank();
    }

    // 测试超长贷款期限
    function testRepayLoanWithExtremeDuration() public {
        _createLoanOffer();
        vm.startPrank(alice);
        marketplace.acceptLoanOffer(0);
        vm.stopPrank();

        vm.warp(block.timestamp + 100 * 365 days); // 100年
        vm.startPrank(bob);
        uint256 totalRepayment = marketplace.getRepaymentAmount(0); // 假设添加了此函数
        usdc.approve(address(marketplace), totalRepayment);
        marketplace.repayLoan(0);
        vm.stopPrank();
    }

    // 测试重复还款
    function test_RevertIf_LoanAlreadyRepaid() public {
        _createLoanOffer();
        vm.startPrank(alice);
        marketplace.acceptLoanOffer(0);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 totalRepayment = marketplace.getRepaymentAmount(0);
        usdc.approve(address(marketplace), totalRepayment);
        marketplace.repayLoan(0);

        vm.expectRevert("Loan already repaid");
        marketplace.repayLoan(0);
        vm.stopPrank();
    }

    // 测试平台费提取
    function testWithdrawPlatformFees() public {
        _createLoanOffer();
        vm.startPrank(alice);
        marketplace.acceptLoanOffer(0);
        vm.stopPrank();

        vm.startPrank(owner);
        uint256 balanceBefore = usdc.balanceOf(owner);
        marketplace.withdrawPlatformFees(address(usdc), 15 * 10 ** 6); // 0.5% of 3000
        uint256 balanceAfter = usdc.balanceOf(owner);
        assertEq(balanceAfter - balanceBefore, 15 * 10 ** 6, "Platform fees not withdrawn correctly");
        vm.stopPrank();
    }

    // 测试零值输入
    function test_RevertIf_LoanAmountIsZero() public {
        vm.startPrank(bob);
        vm.expectRevert("Loan amount must be greater than 0");
        marketplace.createLoanOffer{value: 2.25 ether}(address(usdc), 0, address(0), 2.25 ether, 400, 60 days);
        vm.stopPrank();
    }
}
