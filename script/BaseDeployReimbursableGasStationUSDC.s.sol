// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {ReimbursableGasStationUSDC} from "../src/PayWithERC20/USDC/ReimbursableGasStationUSDC.sol";

contract BaseDeployReimbursableGasStationUSDC is Script {
    // Base mainnet USDC/USD price feed
    address private constant PRICE_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address private constant REIMBURSEMENT_ERC20 = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address private constant TK_GAS_DELEGATE = 0x000066a00056CD44008768E2aF00696e19A30084;
    uint16 private constant GAS_FEE_BASIS_POINTS = 100; // 1% (100 basis points)
    uint256 private constant BASE_GAS_FEE_ERC20 = 10_000; // Base gas fee: 1 cent in USDC (0.01 * 10^6)
    uint256 private constant MAX_GAS_LIMIT_ERC20 = 10_000_000; // Max gas limit: 10 dollars in USDC (10 * 10^6)

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address reimbursementAddress = vm.envAddress("REIMBURSEMENT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        ReimbursableGasStationUSDC gasStation = new ReimbursableGasStationUSDC(
            PRICE_FEED,
            TK_GAS_DELEGATE,
            reimbursementAddress,
            REIMBURSEMENT_ERC20,
            GAS_FEE_BASIS_POINTS,
            BASE_GAS_FEE_ERC20,
            MAX_GAS_LIMIT_ERC20
        );

        console2.log("ReimbursableGasStationUSDC deployed at:", address(gasStation));
        console2.log("Price Feed:", PRICE_FEED);
        console2.log("Reimbursement Address:", reimbursementAddress);

        vm.stopBroadcast();
    }
}
