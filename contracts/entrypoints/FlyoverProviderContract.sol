// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../pegout-contract/PegoutContract.sol";
import "../pegin-contract/PeginContract.sol";
import "../liquidity-provider-contract/LiquidityProviderContract.sol";

contract FlyoverProviderContract is Initializable, OwnableUpgradeable {

    LiquidityProviderContract private lpContract;
    PegoutContract private pegoutContract;
    PeginContract private peginContract;

    function initialize(
        address payable _lpContract,
        address payable _pegoutContract,
        address payable _peginContract
    ) external initializer {
        lpContract = LiquidityProviderContract(_lpContract);
        pegoutContract = PegoutContract(_pegoutContract);
        peginContract = PeginContract(_peginContract);
    }

    modifier onlyEoa() {
        require(tx.origin == msg.sender, "LBC003");
        _;
    }

    function hashQuote(Quotes.PeginQuote calldata quote) public view returns (bytes32) {
        return peginContract.hashQuote(quote);
    }

    function hashPegoutQuote(Quotes.PegOutQuote calldata quote) public view returns (bytes32) {
        return pegoutContract.hashPegoutQuote(quote);
    }

    function isOperational(address addr) external view returns (bool) {
        return lpContract.isOperational(addr);
    }

    function isOperationalForPegout(address addr) external view returns (bool) {
        return lpContract.isOperationalForPegout(addr);
    }

    function getCollateral(address addr) external view returns (uint256) {
        return lpContract.getCollateral(addr);
    }

    function getMinCollateral() external view returns (uint) {
        return lpContract.getMinCollateral();
    }

    function getBalance(address liquidityProvider) public view returns (uint256) {
        return lpContract.getBalance(liquidityProvider);
    }

    function getRewardPercentage() external view returns (uint) {
        return peginContract.getRewardPercentage();
    }

    function getProviderIds() external view returns (uint) {
        return lpContract.getProviderIds();
    }

    function getRegisteredPegOutQuote(
        bytes32 quoteHash
    ) external view returns (Quotes.PegOutQuote memory) {
        return pegoutContract.getRegisteredPegOutQuote(quoteHash);
    }

    function addCollateral() external payable {
        return lpContract.addCollateral{value: msg.value}();
    }

    function addPegoutCollateral() external payable {
        return lpContract.addPegoutCollateral{value: msg.value}();
    }

    function setProviderStatus(uint _providerId, bool status) public {
        return lpContract.setProviderStatus(_providerId, status);
    }

    function deposit() external payable {
        lpContract.deposit{value: msg.value}();
    }

    function withdraw(uint256 amount) external {
        lpContract.withdraw(amount);
    }

    function withdrawCollateral() external {
        lpContract.withdrawCollateral();
    }

    function withdrawPegoutCollateral() external {
        lpContract.withdrawPegoutCollateral();
    }

    function resign() external {
        lpContract.resign();
    }

    function register(
        string memory _name,
        uint _fee,
        uint _quoteExpiration,
        uint _minTransactionValue,
        uint _maxTransactionValue,
        string memory _apiBaseUrl,
        bool _status,
        string memory _providerType
    ) external payable onlyEoa returns (uint) {
        return lpContract.register{value: msg.value}(
            _name,
            _fee,
            _quoteExpiration,
            _minTransactionValue,
            _maxTransactionValue,
            _apiBaseUrl,
            _status,
            _providerType
        );
    }

    function getProviders(
        uint[] calldata providerIds
    ) external view returns (LiquidityProviderContract.LiquidityProvider[] memory) {
        return lpContract.getProviders(providerIds);
    }

    function refundPegOut(
        bytes32 quoteHash,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 partialMerkleTree,
        bytes32[] calldata merkleBranchHashes
    ) public {
        pegoutContract.refundPegOut(quoteHash, btcTx, btcBlockHeaderHash, partialMerkleTree, merkleBranchHashes);
    }

    function registerPegIn(
        Quotes.PeginQuote memory quote,
        bytes memory signature,
        bytes memory btcRawTransaction,
        bytes memory partialMerkleTree,
        uint256 height
    ) public returns (int256) {
        return peginContract.registerPegIn(quote, signature, btcRawTransaction, partialMerkleTree, height);
    }

    function callForUser(
        Quotes.PeginQuote calldata quote
    ) external payable returns (bool) {
        return peginContract.callForUser{value: msg.value}(quote);
    }

    function getBtcBlockTimestamp(
        bytes calldata header
    ) public view returns (uint256) {
        return peginContract.getBtcBlockTimestamp(header);
    }
}