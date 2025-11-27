// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ReimbursableGasStationUSDCFactory} from "../../src/PayWithERC20/USDC/ReimbursableGasStationUSDCFactory.sol";

/// @notice Generic deploy script that:
/// 1. Deploys a `ReimbursableGasStationUSDCFactory` using parameters from `.env`.
/// 2. Uses that factory to create a single `ReimbursableGasStationUSDC` instance.
///
/// All arguments are read from environment variables (see `src/PayWithERC20/env.example`).
contract DeployReimbursableGasStationUSDCAndFactory is Script {
    function run() external {
        // Deployer
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Factory constructor params
        address priceFeed = vm.envAddress("PRICE_FEED");
        address reimbursementErc20 = vm.envAddress("REIMBURSEMENT_ERC20");
        address tkGasDelegate = vm.envAddress("TK_GAS_DELEGATE");

        // Gas station creation params
        bytes32 salt = vm.envBytes32("GAS_STATION_SALT");
        address reimbursementAddress = vm.envAddress("REIMBURSEMENT_ADDRESS");
        uint16 gasFeeBasisPoints = uint16(vm.envUint("GAS_FEE_BASIS_POINTS"));
        uint256 baseGasFeeWei = vm.envUint("BASE_GAS_FEE_WEI");
        uint256 baseGasFeeErc20 = vm.envUint("BASE_GAS_FEE_ERC20");
        uint256 maxDepositLimitErc20 = vm.envUint("MAX_DEPOSIT_LIMIT_ERC20");
        uint256 minimumTransactionGasLimitWei = vm.envUint("MINIMUM_TRANSACTION_GAS_LIMIT_WEI");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy factory
        ReimbursableGasStationUSDCFactory factory =
            new ReimbursableGasStationUSDCFactory(priceFeed, reimbursementErc20, tkGasDelegate);

        console2.log("ReimbursableGasStationUSDCFactory deployed at:", address(factory));
        console2.log("Price Feed:", priceFeed);
        console2.log("Reimbursement ERC20:", reimbursementErc20);
        console2.log("TK Gas Delegate:", tkGasDelegate);

        // 2. Create a gas station instance via the factory
        address gasStation = factory.createReimbursableGasStation(
            salt,
            reimbursementAddress,
            gasFeeBasisPoints,
            baseGasFeeWei,
            baseGasFeeErc20,
            maxDepositLimitErc20,
            minimumTransactionGasLimitWei
        );

        console2.log("ReimbursableGasStationUSDC created at:", gasStation);
        console2.log("Reimbursement Address:", reimbursementAddress);
        console2.log("GAS_FEE_BASIS_POINTS:", gasFeeBasisPoints);
        console2.log("BASE_GAS_FEE_WEI:", baseGasFeeWei);
        console2.log("BASE_GAS_FEE_ERC20:", baseGasFeeErc20);
        console2.log("MAX_DEPOSIT_LIMIT_ERC20:", maxDepositLimitErc20);
        console2.log("MINIMUM_TRANSACTION_GAS_LIMIT_WEI:", minimumTransactionGasLimitWei);

        vm.stopBroadcast();
    }
}
