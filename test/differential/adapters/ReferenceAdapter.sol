// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {QuotesV2} from "../../../src/legacy/QuotesV2.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDifferentialAdapter} from "./IDifferentialAdapter.sol";

contract ReferenceAdapter is IDifferentialAdapter {
    struct LegacyLiquidityProvider {
        uint256 id;
        address provider;
        string name;
        string apiBaseUrl;
        bool status;
        string providerType;
    }

    IDifferentialAdapter private immutable _target;
    uint256 private immutable _expectedMinPegIn;
    uint256 private immutable _expectedDustThreshold;
    Vm private constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    constructor(
        address target_,
        uint256 expectedMinPegIn_,
        uint256 expectedDustThreshold_
    ) {
        _target = IDifferentialAdapter(target_);
        _expectedMinPegIn = expectedMinPegIn_;
        _expectedDustThreshold = expectedDustThreshold_;
    }

    function getBridgeAddress() external view returns (address) {
        return _target.bridge();
    }

    function getMinPegIn() external view returns (uint256) {
        return _expectedMinPegIn;
    }

    function getMinCollateral() external view returns (uint256) {
        return _target.getMinCollateral();
    }

    function getRewardPercentage() external view returns (uint256) {
        return _target.getRewardPercentage();
    }

    function getResignDelayBlocks() external view returns (uint256) {
        return _target.getResignDelayBlocks();
    }

    function getDustThreshold() external view returns (uint256) {
        return _expectedDustThreshold;
    }

    function hashQuote(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32) {
        return _target.hashQuote(quote);
    }

    function hashPegoutQuote(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32) {
        return _target.hashPegoutQuote(quote);
    }

    function bridge() external view returns (address) {
        return _target.bridge();
    }

    function minPegIn() external view returns (uint256) {
        return _expectedMinPegIn;
    }

    function minCollateral() external view returns (uint256) {
        return _target.getMinCollateral();
    }

    function hashPegInQuoteRaw(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32) {
        return _target.hashQuote(quote);
    }

    function hashPegInQuoteForTarget(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32) {
        quote.lbcAddress = address(_target);
        return _target.hashQuote(quote);
    }

    function hashPegOutQuoteRaw(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32) {
        return _target.hashPegoutQuote(quote);
    }

    function hashPegOutQuoteForTarget(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32) {
        quote.lbcAddress = address(_target);
        return _target.hashPegoutQuote(quote);
    }

    function registerProvider(
        string memory name,
        string memory apiBaseUrl,
        bool status,
        ProviderType providerType
    ) external payable returns (uint256) {
        vm.prank(msg.sender, msg.sender);
        (bool ok, bytes memory data) = address(_target).call{value: msg.value}(
            abi.encodeWithSignature(
                "register(string,string,bool,string)",
                name,
                apiBaseUrl,
                status,
                _toLegacyProviderType(providerType)
            )
        );
        require(ok, "register failed");
        return abi.decode(data, (uint256));
    }

    function updateProviderMetadata(
        string memory name,
        string memory apiBaseUrl
    ) external {
        vm.prank(msg.sender, msg.sender);
        (bool ok, ) = address(_target).call(
            abi.encodeWithSignature(
                "updateProvider(string,string)",
                name,
                apiBaseUrl
            )
        );
        require(ok, "updateProvider failed");
    }

    function setProviderStatusById(uint256 providerId, bool status) external {
        vm.prank(msg.sender, msg.sender);
        (bool ok, ) = address(_target).call(
            abi.encodeWithSignature(
                "setProviderStatus(uint256,bool)",
                providerId,
                status
            )
        );
        require(ok, "setProviderStatus failed");
    }

    function getProviderByAddress(
        address providerAddress
    ) external view returns (LiquidityProviderView memory) {
        (bool ok, bytes memory data) = address(_target).staticcall(
            abi.encodeWithSignature("getProvider(address)", providerAddress)
        );
        require(ok, "getProvider failed");
        (
            uint256 id,
            address provider,
            string memory name,
            string memory apiBaseUrl,
            bool status,
            string memory providerType
        ) = abi.decode(data, (uint256, address, string, string, bool, string));
        return
            _toDiffProvider(
                id,
                provider,
                name,
                apiBaseUrl,
                status,
                providerType
            );
    }

    function getListedProviders()
        external
        view
        returns (LiquidityProviderView[] memory)
    {
        (bool ok, bytes memory data) = address(_target).staticcall(
            abi.encodeWithSignature("getProviders()")
        );
        require(ok, "getProviders failed");
        LegacyLiquidityProvider[] memory providers = abi.decode(
            data,
            (LegacyLiquidityProvider[])
        );
        uint256 len = providers.length;
        LiquidityProviderView[] memory out = new LiquidityProviderView[](len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = _toDiffProvider(
                providers[i].id,
                providers[i].provider,
                providers[i].name,
                providers[i].apiBaseUrl,
                providers[i].status,
                providers[i].providerType
            );
        }
        return out;
    }

    function isProviderOperational(
        ProviderType providerType,
        address providerAddress
    ) external view returns (bool) {
        (bool okPegIn, bytes memory dataPegIn) = address(_target).staticcall(
            abi.encodeWithSignature("isOperational(address)", providerAddress)
        );
        require(okPegIn, "isOperational failed");
        bool pegInOperational = abi.decode(dataPegIn, (bool));

        (bool okPegOut, bytes memory dataPegOut) = address(_target).staticcall(
            abi.encodeWithSignature(
                "isOperationalForPegout(address)",
                providerAddress
            )
        );
        require(okPegOut, "isOperationalForPegout failed");
        bool pegOutOperational = abi.decode(dataPegOut, (bool));

        if (providerType == ProviderType.PegIn) {
            return pegInOperational;
        }
        if (providerType == ProviderType.PegOut) {
            return pegOutOperational;
        }
        return pegInOperational && pegOutOperational;
    }

    function _toLegacyProviderType(
        ProviderType providerType
    ) private pure returns (string memory) {
        if (providerType == ProviderType.PegIn) return "pegin";
        if (providerType == ProviderType.PegOut) return "pegout";
        return "both";
    }

    function _fromLegacyProviderType(
        string memory providerType
    ) private pure returns (ProviderType) {
        bytes32 t = keccak256(bytes(providerType));
        if (t == keccak256(bytes("pegin"))) return ProviderType.PegIn;
        if (t == keccak256(bytes("pegout"))) return ProviderType.PegOut;
        return ProviderType.Both;
    }

    function _toDiffProvider(
        uint256 id,
        address providerAddress,
        string memory name,
        string memory apiBaseUrl,
        bool status,
        string memory providerType
    ) private pure returns (LiquidityProviderView memory) {
        return
            LiquidityProviderView({
                id: id,
                providerAddress: providerAddress,
                status: status,
                providerType: _fromLegacyProviderType(providerType),
                name: name,
                apiBaseUrl: apiBaseUrl
            });
    }
}
