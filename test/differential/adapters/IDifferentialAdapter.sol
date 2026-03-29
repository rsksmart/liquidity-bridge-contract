// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {QuotesV2} from "../../../src/legacy/QuotesV2.sol";

/// @title Differential Adapter Interface
/// @notice Used by differential tests to compare reference and candidate systems.
/// @dev Implementations normalize different contract layouts behind a shared API.
interface IDifferentialAdapter {
    enum ProviderType {
        PegIn,
        PegOut,
        Both
    }

    struct LiquidityProviderView {
        uint256 id;
        address providerAddress;
        bool status;
        ProviderType providerType;
        string name;
        string apiBaseUrl;
    }

    function getBridgeAddress() external view returns (address);

    function getMinPegIn() external view returns (uint256);

    function getMinCollateral() external view returns (uint256);

    function getRewardPercentage() external view returns (uint256);

    function getResignDelayBlocks() external view returns (uint256);

    function getDustThreshold() external view returns (uint256);

    function hashQuote(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32);

    function hashPegoutQuote(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32);

    function bridge() external view returns (address);

    function minPegIn() external view returns (uint256);

    function minCollateral() external view returns (uint256);

    /// @notice Hashes a peg-in quote using the quote-provided target field as-is.
    /// @param quote Peg-in quote to hash.
    /// @return Quote hash.
    function hashPegInQuoteRaw(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32);

    /// @notice Hashes a peg-in quote forcing implementer-specific target normalization.
    /// @param quote Peg-in quote to hash.
    /// @return Quote hash.
    function hashPegInQuoteForTarget(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32);

    /// @notice Hashes a peg-out quote using the quote-provided target field as-is.
    /// @param quote Peg-out quote to hash.
    /// @return Quote hash.
    function hashPegOutQuoteRaw(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32);

    /// @notice Hashes a peg-out quote forcing implementer-specific target normalization.
    /// @param quote Peg-out quote to hash.
    /// @return Quote hash.
    function hashPegOutQuoteForTarget(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32);

    function registerProvider(
        string memory name,
        string memory apiBaseUrl,
        bool status,
        ProviderType providerType
    ) external payable returns (uint256);

    function updateProviderMetadata(
        string memory name,
        string memory apiBaseUrl
    ) external;

    function setProviderStatusById(uint256 providerId, bool status) external;

    function getProviderByAddress(
        address providerAddress
    ) external view returns (LiquidityProviderView memory);

    function getListedProviders()
        external
        view
        returns (LiquidityProviderView[] memory);

    function isProviderOperational(
        ProviderType providerType,
        address providerAddress
    ) external view returns (bool);
}
