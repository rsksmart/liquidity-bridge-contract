// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

/// @title DeployLibraries
/// @notice Deploys Quotes, SignatureValidator, and BtcUtils required by PegIn/PegOut
/// @dev Run before deploy-flyover-* on a network without library entries in addresses.json.
///      After broadcast, copy the logged addresses into addresses.json before deploy-flyover-*.
contract DeployLibraries is Script {
    struct DeploymentResult {
        address quotes;
        address signatureValidator;
        address btcUtils;
    }

    function run() external returns (DeploymentResult memory result) {
        HelperConfig helper = new HelperConfig();
        uint256 deployerKey = helper.getDeployerPrivateKey();

        vm.startBroadcast(deployerKey);

        result.quotes = deployCode("src/libraries/Quotes.sol:Quotes");
        result.signatureValidator = deployCode(
            "src/libraries/SignatureValidator.sol:SignatureValidator"
        );
        result.btcUtils = deployCode(
            "node_modules/@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol:BtcUtils"
        );

        vm.stopBroadcast();

        _log(result);
    }

    function _log(DeploymentResult memory r) private pure {
        console.log("=== Flyover Libraries Deployed ===");
        console.log("Quotes:", r.quotes);
        console.log("SignatureValidator:", r.signatureValidator);
        console.log("BtcUtils:", r.btcUtils);
        console.log("");
        console.log("Next steps:");
        console.log(
            "  1. Add the addresses above to addresses.json for your network"
        );
        console.log("  2. make deploy-flyover-fork NETWORK=<network>");
    }
}
