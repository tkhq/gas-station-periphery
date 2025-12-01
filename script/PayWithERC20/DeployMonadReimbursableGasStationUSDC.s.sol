// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ReimbursableGasStationUSDCFactory} from "../../src/PayWithERC20/USDC/ReimbursableGasStationUSDCFactory.sol";

/// @notice Deploy script for Monad network
/// Uses hardcoded addresses for USDC and oracle on Monad
contract DeployMonadReimbursableGasStationUSDC is Script {
    function run() external {
        // Deployer
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Monad-specific addresses
        address priceFeed = 0xBcD78f76005B7515837af6b50c7C52BCf73822fb; // Oracle
        address reimbursementERC20 = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603; // USDC
        address tkGasDelegate = 0x000066a00056CD44008768E2aF00696e19A30084; // Same across all networks

        // Gas station creation params from .env
        bytes32 salt = vm.envBytes32("GAS_STATION_SALT");
        address reimbursementAddress = vm.envAddress("REIMBURSEMENT_ADDRESS");
        uint16 gasFeeBasisPoints = uint16(vm.envUint("GAS_FEE_BASIS_POINTS"));
        uint256 baseGasFeeWei = vm.envUint("BASE_GAS_FEE_WEI");
        uint256 baseGasFeeERC20 = vm.envUint("BASE_GAS_FEE_ERC20");
        uint256 maxDepositLimitERC20 = vm.envUint("MAX_DEPOSIT_LIMIT_ERC20");
        uint256 minimumTransactionGasLimitWei = vm.envUint("MINIMUM_TRANSACTION_GAS_LIMIT_WEI");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy factory
        ReimbursableGasStationUSDCFactory factory =
            new ReimbursableGasStationUSDCFactory(priceFeed, reimbursementERC20, tkGasDelegate);

        console2.log("ReimbursableGasStationUSDCFactory deployed at:", address(factory));
        console2.log("Price Feed:", priceFeed);
        console2.log("Reimbursement ERC20:", reimbursementERC20);
        console2.log("TK Gas Delegate:", tkGasDelegate);

        // 2. Create a gas station instance via the factory
        address gasStation = factory.createReimbursableGasStation(
            salt,
            reimbursementAddress,
            gasFeeBasisPoints,
            baseGasFeeWei,
            baseGasFeeERC20,
            maxDepositLimitERC20,
            minimumTransactionGasLimitWei
        );

        console2.log("ReimbursableGasStationUSDC created at:", gasStation);
        console2.log("Reimbursement Address:", reimbursementAddress);
        console2.log("GAS_FEE_BASIS_POINTS:", gasFeeBasisPoints);
        console2.log("BASE_GAS_FEE_WEI:", baseGasFeeWei);
        console2.log("BASE_GAS_FEE_ERC20:", baseGasFeeERC20);
        console2.log("MAX_DEPOSIT_LIMIT_ERC20:", maxDepositLimitERC20);
        console2.log("MINIMUM_TRANSACTION_GAS_LIMIT_WEI:", minimumTransactionGasLimitWei);

        vm.stopBroadcast();
    }
}

