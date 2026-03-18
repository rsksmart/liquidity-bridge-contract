// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {QuotesV2} from "../../../src/legacy/QuotesV2.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";
import {PegInContract} from "../../../src/PegInContract.sol";
import {PegOutContract} from "../../../src/PegOutContract.sol";
import {CollateralManagementContract} from "../../../src/CollateralManagement.sol";
import {IFlyoverDiscovery} from "../../../src/interfaces/IFlyoverDiscovery.sol";
import {IDifferentialAdapter} from "./IDifferentialAdapter.sol";

contract CandidateAdapter is IDifferentialAdapter {
    PegInContract private immutable _pegIn;
    PegOutContract private immutable _pegOut;
    CollateralManagementContract private immutable _collateral;
    IFlyoverDiscovery private immutable _discovery;
    address private immutable _bridge;

    constructor(
        address pegInTarget_,
        address pegOutTarget_,
        address collateralTarget_,
        address discoveryTarget_,
        address bridge_
    ) {
        _pegIn = PegInContract(payable(pegInTarget_));
        _pegOut = PegOutContract(payable(pegOutTarget_));
        _collateral = CollateralManagementContract(payable(collateralTarget_));
        _discovery = IFlyoverDiscovery(discoveryTarget_);
        _bridge = bridge_;
    }

    function getBridgeAddress() external view returns (address) {
        return _bridge;
    }

    function getMinPegIn() external view returns (uint256) {
        return _pegIn.getMinPegIn();
    }

    function getMinCollateral() external view returns (uint256) {
        return _collateral.getMinCollateral();
    }

    function getRewardPercentage() external view returns (uint256) {
        return _collateral.getRewardPercentage();
    }

    function getResignDelayBlocks() external view returns (uint256) {
        return _collateral.getResignDelayInBlocks();
    }

    function getDustThreshold() external view returns (uint256) {
        return _pegIn.dustThreshold();
    }

    function hashQuote(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32) {
        Quotes.PegInQuote memory q = _toPegInQuote(quote, address(_pegIn));
        return _pegIn.hashPegInQuote(q);
    }

    function hashPegoutQuote(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32) {
        Quotes.PegOutQuote memory q = _toPegOutQuote(quote, address(_pegOut));
        return _pegOut.hashPegOutQuote(q);
    }

    function bridge() external view returns (address) {
        return _bridge;
    }

    function minPegIn() external view returns (uint256) {
        return _pegIn.getMinPegIn();
    }

    function minCollateral() external view returns (uint256) {
        return _collateral.getMinCollateral();
    }

    function hashPegInQuoteRaw(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32) {
        Quotes.PegInQuote memory q = _toPegInQuote(quote, quote.lbcAddress);
        return _pegIn.hashPegInQuote(q);
    }

    function hashPegInQuoteForTarget(
        QuotesV2.PeginQuote memory quote
    ) external view returns (bytes32) {
        Quotes.PegInQuote memory q = _toPegInQuote(quote, address(_pegIn));
        return _pegIn.hashPegInQuote(q);
    }

    function hashPegOutQuoteRaw(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32) {
        Quotes.PegOutQuote memory q = _toPegOutQuote(quote, quote.lbcAddress);
        return _pegOut.hashPegOutQuote(q);
    }

    function hashPegOutQuoteForTarget(
        QuotesV2.PegOutQuote memory quote
    ) external view returns (bytes32) {
        Quotes.PegOutQuote memory q = _toPegOutQuote(quote, address(_pegOut));
        return _pegOut.hashPegOutQuote(q);
    }

    function registerProvider(
        string memory name,
        string memory apiBaseUrl,
        bool status,
        ProviderType providerType
    ) external payable returns (uint256) {
        return
            _discovery.register{value: msg.value}(
                name,
                apiBaseUrl,
                status,
                _toFlyoverProviderType(providerType)
            );
    }

    function updateProviderMetadata(
        string memory name,
        string memory apiBaseUrl
    ) external {
        _discovery.updateProvider(name, apiBaseUrl);
    }

    function setProviderStatusById(uint256 providerId, bool status) external {
        _discovery.setProviderStatus(providerId, status);
    }

    function getProviderByAddress(
        address providerAddress
    ) external view returns (LiquidityProviderView memory) {
        return _toDiffProvider(_discovery.getProvider(providerAddress));
    }

    function getListedProviders()
        external
        view
        returns (LiquidityProviderView[] memory)
    {
        Flyover.LiquidityProvider[] memory providers = _discovery
            .getProviders();
        LiquidityProviderView[] memory out = new LiquidityProviderView[](
            providers.length
        );
        for (uint256 i = 0; i < providers.length; i++) {
            out[i] = _toDiffProvider(providers[i]);
        }
        return out;
    }

    function isProviderOperational(
        ProviderType providerType,
        address providerAddress
    ) external view returns (bool) {
        return
            _discovery.isOperational(
                _toFlyoverProviderType(providerType),
                providerAddress
            );
    }

    function _toPegInQuote(
        QuotesV2.PeginQuote memory quote,
        address lbcAddress
    ) private view returns (Quotes.PegInQuote memory) {
        return
            Quotes.PegInQuote({
                chainId: block.chainid,
                callFee: quote.callFee,
                penaltyFee: quote.penaltyFee,
                value: quote.value,
                gasFee: quote.gasFee,
                fedBtcAddress: quote.fedBtcAddress,
                lbcAddress: lbcAddress,
                liquidityProviderRskAddress: quote.liquidityProviderRskAddress,
                contractAddress: quote.contractAddress,
                rskRefundAddress: quote.rskRefundAddress,
                nonce: quote.nonce,
                gasLimit: quote.gasLimit,
                agreementTimestamp: quote.agreementTimestamp,
                timeForDeposit: quote.timeForDeposit,
                callTime: quote.callTime,
                depositConfirmations: quote.depositConfirmations,
                callOnRegister: quote.callOnRegister,
                btcRefundAddress: quote.btcRefundAddress,
                liquidityProviderBtcAddress: quote.liquidityProviderBtcAddress,
                data: quote.data
            });
    }

    function _toPegOutQuote(
        QuotesV2.PegOutQuote memory quote,
        address lbcAddress
    ) private view returns (Quotes.PegOutQuote memory) {
        return
            Quotes.PegOutQuote({
                chainId: block.chainid,
                callFee: quote.callFee,
                penaltyFee: quote.penaltyFee,
                value: quote.value,
                gasFee: quote.gasFee,
                lbcAddress: lbcAddress,
                lpRskAddress: quote.lpRskAddress,
                rskRefundAddress: quote.rskRefundAddress,
                nonce: quote.nonce,
                agreementTimestamp: quote.agreementTimestamp,
                depositDateLimit: quote.depositDateLimit,
                transferTime: quote.transferTime,
                expireDate: quote.expireDate,
                expireBlock: quote.expireBlock,
                depositConfirmations: quote.depositConfirmations,
                transferConfirmations: quote.transferConfirmations,
                depositAddress: quote.deposityAddress,
                btcRefundAddress: quote.btcRefundAddress,
                lpBtcAddress: quote.lpBtcAddress
            });
    }

    function _toFlyoverProviderType(
        ProviderType providerType
    ) private pure returns (Flyover.ProviderType) {
        if (providerType == ProviderType.PegIn) {
            return Flyover.ProviderType.PegIn;
        }
        if (providerType == ProviderType.PegOut) {
            return Flyover.ProviderType.PegOut;
        }
        return Flyover.ProviderType.Both;
    }

    function _fromFlyoverProviderType(
        Flyover.ProviderType providerType
    ) private pure returns (ProviderType) {
        if (providerType == Flyover.ProviderType.PegIn) {
            return ProviderType.PegIn;
        }
        if (providerType == Flyover.ProviderType.PegOut) {
            return ProviderType.PegOut;
        }
        return ProviderType.Both;
    }

    function _toDiffProvider(
        Flyover.LiquidityProvider memory provider
    ) private pure returns (LiquidityProviderView memory) {
        return
            LiquidityProviderView({
                id: provider.id,
                providerAddress: provider.providerAddress,
                status: provider.status,
                providerType: _fromFlyoverProviderType(provider.providerType),
                name: provider.name,
                apiBaseUrl: provider.apiBaseUrl
            });
    }
}
