// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import "../../src/interfaces/IFlashLoanReceiver.sol";
import "../../src/interfaces/IERC20.sol";

contract MockLendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata /* modes */,
        address onBehalfOf,
        bytes calldata params,
        uint16 /* referralCode */
    ) external {
        // 转移资产给接收者
        for (uint i = 0; i < assets.length; i++) {
            IERC20(assets[i]).transfer(receiverAddress, amounts[i]);
        }
        
        // 计算手续费 (0.09%)
        uint256[] memory premiums = new uint256[](amounts.length);
        for (uint i = 0; i < amounts.length; i++) {
            premiums[i] = (amounts[i] * 9) / 10000;
        }
        
        // 调用接收者的 executeOperation 函数
        bool success = IFlashLoanReceiver(receiverAddress).executeOperation(
            assets,
            amounts,
            premiums,
            onBehalfOf,
            params
        );
        require(success, "Flash loan failed");
        
        // 从接收者那里收回资产和手续费
        for (uint i = 0; i < assets.length; i++) {
            IERC20(assets[i]).transferFrom(
                receiverAddress,
                address(this),
                amounts[i] + premiums[i]
            );
        }
    }
} 