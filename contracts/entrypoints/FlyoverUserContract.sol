// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../pegout-contract/PegoutContract.sol";
import "../liquidity-provider-contract/LiquidityProviderContract.sol";

contract FlyoverUserContract is Initializable, OwnableUpgradeable {

    LiquidityProviderContract private lpContract;
    PegoutContract private pegoutContract;

    function initialize(
        address payable _lpContract,
        address payable _pegoutContract
    ) external initializer {
        lpContract = LiquidityProviderContract(_lpContract);
        pegoutContract = PegoutContract(_pegoutContract);
    }

    function getProviders(
        uint[] calldata providerIds
    ) external view returns (LiquidityProviderContract.LiquidityProvider[] memory) {
        return lpContract.getProviders(providerIds);
    }

    function refundUserPegOut(bytes32 quoteHash) public {
        pegoutContract.refundUserPegOut(quoteHash);
    }

    function depositPegout(
        Quotes.PegOutQuote calldata quote,
        bytes calldata signature
    ) external payable {
        pegoutContract.depositPegout{value: msg.value}(msg.sender, quote, signature);
    }
    
    
}