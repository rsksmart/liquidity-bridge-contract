// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Vm} from "lib/forge-std/src/Vm.sol";

library BtcAddressParserLib {
    string constant HELPER_SCRIPT_BTC_ADDRESS =
        "forge-scripts/helpers/parse-btc-address.ts";

    function parseBtcAddress(
        Vm vm,
        string memory btcAddress
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_BTC_ADDRESS;
        inputs[3] = btcAddress;

        bytes memory result = vm.ffi(inputs);
        return result;
    }

    function parseFedBtcAddress(
        Vm vm,
        string memory btcAddress
    ) internal returns (bytes20) {
        bytes memory decoded = parseBtcAddress(vm, btcAddress);
        require(decoded.length >= 21, "Invalid fedBtcAddress length");

        bytes memory sliced = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            sliced[i] = decoded[i + 1];
        }

        return bytes20(sliced);
    }
}

abstract contract BtcAddressParser {
    function _getVm() internal pure returns (Vm) {
        return Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    }

    function parseBtcAddress(
        string memory btcAddress
    ) internal returns (bytes memory) {
        return BtcAddressParserLib.parseBtcAddress(_getVm(), btcAddress);
    }

    function parseFedBtcAddress(
        string memory btcAddress
    ) internal returns (bytes20) {
        return BtcAddressParserLib.parseFedBtcAddress(_getVm(), btcAddress);
    }
}
