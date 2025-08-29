// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title ChangeOwnerToMultiSig
 * @notice Foundry script to transfer ownership of LiquidityBridgeContract proxy to a multisig wallet
 *
 * @dev This script performs two ownership transfers:
 *      1. Contract ownership (via transferOwnership on the proxy)
 *      2. Proxy admin ownership (via transferOwnership on the ProxyAdmin)
 *
 * Usage:
 *   forge script forge-scripts/ChangeOwnerToMultiSig.s.sol:ChangeOwnerToMultiSig --rpc-url <RPC_URL> --broadcast --verify
 *
 * Environment Variables Required:
 *   - EXISTING_PROXY_MAINNET or EXISTING_PROXY_TESTNET: Address of the deployed proxy
 *   - MAINNET_SIGNER_PRIVATE_KEY or TESTNET_SIGNER_PRIVATE_KEY: Private key of current owner
 *   - MULTISIG_ADDRESS_MAINNET or MULTISIG_ADDRESS_TESTNET: Address of the multisig wallet
 *   - MULTISIG_OWNER_1_MAINNET through MULTISIG_OWNER_4_MAINNET: Owner addresses for mainnet
 *   - MULTISIG_OWNER_1_TESTNET through MULTISIG_OWNER_5_TESTNET: Owner addresses for testnet
 *
 * Note: If environment variables are not provided, the script will use default hardcoded values
 *       from the multisig-owners.json file. You can override these by setting the environment variables.
 *
 * Networks Supported:
 *   - RSK Mainnet (Chain ID: 30)
 *   - RSK Testnet (Chain ID: 31)
 *
 * @author Generated for Liquidity Bridge Contract
 */

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {LiquidityBridgeContractV2} from "../contracts/legacy/LiquidityBridgeContractV2.sol";
import {LiquidityBridgeContractAdmin} from "../contracts/legacy/LiquidityBridgeContractAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface IGnosisSafe {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function isOwner(address owner) external view returns (bool);
}

contract ChangeOwnerToMultiSig is Script {
    struct MultisigConfig {
        address multisigAddress;
        address[] expectedOwners;
    }

    function run() external {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helper.getConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        address deployer = vm.rememberKey(deployerKey);

        // Get multisig configuration based on chain ID
        MultisigConfig memory multisigConfig = getMultisigConfig();

        require(multisigConfig.multisigAddress != address(0), "Multisig address not found for this network");
        require(multisigConfig.expectedOwners.length > 0, "No expected owners configured");

        // Get the existing proxy address from environment or config
        address proxyAddress = cfg.existingProxy;
        require(proxyAddress != address(0), "Proxy address must be provided");

        console.log("=== Changing Owner to MultiSig ===");
        console.log("Network Chain ID:", block.chainid);
        console.log("Multisig Address:", multisigConfig.multisigAddress);
        console.log("Proxy Address:", proxyAddress);
        console.log("Current Deployer:", deployer);

        // Validate multisig before proceeding
        _validateMultisig(multisigConfig.multisigAddress, multisigConfig.expectedOwners);

        vm.startBroadcast(deployerKey);

        // Transfer contract ownership
        _transferContractOwnership(proxyAddress, multisigConfig.multisigAddress);

        // Transfer proxy admin ownership
        _transferProxyAdminOwnership(proxyAddress, multisigConfig.multisigAddress);

        vm.stopBroadcast();

        console.log("=== Ownership Transfer Complete ===");
        console.log("New Owner:", multisigConfig.multisigAddress);
    }

    function getMultisigConfig() internal view returns (MultisigConfig memory) {
        uint256 chainId = block.chainid;

        if (chainId == 30) {
            // RSK Mainnet
            address[] memory owners = new address[](4);
            owners[0] = vm.envOr("MULTISIG_OWNER_1_MAINNET", address(0xd50C4c5577229C81b19FE1c7D413c2D79CcF7901));
            owners[1] = vm.envOr("MULTISIG_OWNER_2_MAINNET", address(0x15105d3E5F7752F0F7ea0e7B1F3B113701080355));
            owners[2] = vm.envOr("MULTISIG_OWNER_3_MAINNET", address(0xA420aF120Ec6515870B65e811Fa7cE147d491402));
            owners[3] = vm.envOr("MULTISIG_OWNER_4_MAINNET", address(0xA3FD0eeDCA5Ba7504e19B7e0660F21d25FEFE77f));

            return MultisigConfig({
                multisigAddress: vm.envOr("MULTISIG_ADDRESS_MAINNET", address(0x633D1233eD6251108b61A8365CEEd271BF3e3C9b)),
                expectedOwners: owners
            });
        } else if (chainId == 31) {
            // RSK Testnet
            address[] memory owners = new address[](5);
            owners[0] = vm.envOr("MULTISIG_OWNER_1_TESTNET", address(0x8E925445BdA88C9F980976dB098Cb1c450BFc719));
            owners[1] = vm.envOr("MULTISIG_OWNER_2_TESTNET", address(0xF18eD4047ee49D26034AEA5Dafdb0e1895E8DDc1));
            owners[2] = vm.envOr("MULTISIG_OWNER_3_TESTNET", address(0xbd98f2cA40b4Ab54161aC29120251e7d0A4C666E));
            owners[3] = vm.envOr("MULTISIG_OWNER_4_TESTNET", address(0x892813507Bf3aBF2890759d2135Ec34f4909Fea5));
            owners[4] = vm.envOr("MULTISIG_OWNER_5_TESTNET", address(0x1e0a10395E9DeBD5C109bd1116fFfAa3F4a543B2));

            return MultisigConfig({
                multisigAddress: vm.envOr("MULTISIG_ADDRESS_TESTNET", address(0x27ad02ABf893F8e01f0089EDE607A76FbB3F1Cd3)),
                expectedOwners: owners
            });
        } else {
            // Local/Development - return empty config
            address[] memory emptyOwners = new address[](0);
            return MultisigConfig({
                multisigAddress: address(0),
                expectedOwners: emptyOwners
            });
        }
    }

    function _validateMultisig(address multisigAddress, address[] memory expectedOwners) internal view {
        console.log("Validating multisig configuration...");

        // Check if the address has code (is a contract)
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(multisigAddress)
        }
        require(codeSize > 0, "Multisig address is not a contract");

        try IGnosisSafe(multisigAddress).getOwners() returns (address[] memory actualOwners) {
            console.log("Multisig owners count:", actualOwners.length);
            console.log("Expected owners count:", expectedOwners.length);

            // Validate that all expected owners are present
            for (uint256 i = 0; i < expectedOwners.length; i++) {
                bool found = false;
                for (uint256 j = 0; j < actualOwners.length; j++) {
                    if (actualOwners[j] == expectedOwners[i]) {
                        found = true;
                        break;
                    }
                }
                require(found, string(abi.encodePacked("Expected owner not found: ", vm.toString(expectedOwners[i]))));
            }

            console.log("Multisig validation successful");
        } catch {
            revert("Failed to validate multisig - not a valid Safe contract");
        }
    }

    function _transferContractOwnership(address proxyAddress, address newOwner) internal {
        console.log("Transferring contract ownership...");

        LiquidityBridgeContractV2 contract_ = LiquidityBridgeContractV2(payable(proxyAddress));

        address currentOwner = contract_.owner();
        console.log("Current contract owner:", currentOwner);

        if (currentOwner == newOwner) {
            console.log("Contract ownership already set to multisig");
            return;
        }

        // Get the current deployer address
        address currentDeployer = vm.addr(vm.envUint(block.chainid == 30 ? "MAINNET_SIGNER_PRIVATE_KEY" : "TESTNET_SIGNER_PRIVATE_KEY"));
        require(currentOwner == currentDeployer, "Only current owner can transfer ownership");

        contract_.transferOwnership(newOwner);

        // Verify the transfer
        address verifyOwner = contract_.owner();
        require(verifyOwner == newOwner, "Contract ownership transfer failed");

        console.log("Contract ownership transferred successfully to:", newOwner);
    }

    function _transferProxyAdminOwnership(address proxyAddress, address newOwner) internal {
        console.log("Transferring proxy admin ownership...");

        // Get the admin address from the proxy
        bytes32 ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 adminBytes = vm.load(proxyAddress, ADMIN_SLOT);
        address adminAddress = address(uint160(uint256(adminBytes)));

        console.log("Proxy admin address:", adminAddress);
        require(adminAddress != address(0), "Admin address not found");

        LiquidityBridgeContractAdmin admin = LiquidityBridgeContractAdmin(adminAddress);

        address currentAdminOwner = admin.owner();
        console.log("Current admin owner:", currentAdminOwner);

        if (currentAdminOwner == newOwner) {
            console.log("Proxy admin ownership already set to multisig");
            return;
        }

        // Check if the current deployer is the admin owner
        address currentDeployer = vm.addr(vm.envUint(block.chainid == 30 ? "MAINNET_SIGNER_PRIVATE_KEY" : "TESTNET_SIGNER_PRIVATE_KEY"));

        if (currentAdminOwner != currentDeployer) {
            console.log("WARNING: Current admin owner is different from deployer!");
            console.log("Admin owner:", currentAdminOwner);
            console.log("Deployer:", currentDeployer);
            console.log("You need to run this script with the admin owner's private key, or transfer admin ownership first.");
            console.log("Skipping proxy admin ownership transfer...");
            return;
        }

        admin.transferOwnership(newOwner);

        // Verify the transfer
        address verifyAdminOwner = admin.owner();
        require(verifyAdminOwner == newOwner, "Proxy admin ownership transfer failed");

        console.log("Proxy admin ownership transferred successfully to:", newOwner);
    }

    // Helper function to run with custom multisig address (for testing or override)
    function runWithCustomMultisig(address customMultisigAddress) external {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helper.getConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        vm.rememberKey(deployerKey);

        address proxyAddress = cfg.existingProxy;
        require(proxyAddress != address(0), "Proxy address must be provided");
        require(customMultisigAddress != address(0), "Custom multisig address cannot be zero");

        console.log("=== Changing Owner to Custom MultiSig ===");
        console.log("Custom Multisig Address:", customMultisigAddress);
        console.log("Proxy Address:", proxyAddress);

        vm.startBroadcast(deployerKey);

        // Transfer contract ownership
        _transferContractOwnership(proxyAddress, customMultisigAddress);

        // Transfer proxy admin ownership
        _transferProxyAdminOwnership(proxyAddress, customMultisigAddress);

        vm.stopBroadcast();

        console.log("=== Custom Ownership Transfer Complete ===");
    }

    // Helper function to transfer only proxy admin ownership (useful when admin owner is different)
    function transferProxyAdminOnly() external {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helper.getConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        vm.rememberKey(deployerKey);

        // Get multisig configuration
        MultisigConfig memory multisigConfig = getMultisigConfig();
        require(multisigConfig.multisigAddress != address(0), "Multisig address not found for this network");

        address proxyAddress = cfg.existingProxy;
        require(proxyAddress != address(0), "Proxy address must be provided");

        console.log("=== Transferring Proxy Admin Ownership Only ===");
        console.log("Multisig Address:", multisigConfig.multisigAddress);
        console.log("Proxy Address:", proxyAddress);

        vm.startBroadcast(deployerKey);
        _transferProxyAdminOwnership(proxyAddress, multisigConfig.multisigAddress);
        vm.stopBroadcast();

        console.log("=== Proxy Admin Ownership Transfer Complete ===");
    }
}
