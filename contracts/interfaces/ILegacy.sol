// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {QuotesV2} from "../legacy/QuotesV2.sol";

interface ILegacyLiquidityBridgeContract {
    function register(
        string memory name,
        string memory apiBaseUrl,
        bool status,
        string memory providerType
    ) external payable returns (uint);

    function depositPegout(
        QuotesV2.PegOutQuote memory quote,
        bytes memory signature
    ) external payable;
}
