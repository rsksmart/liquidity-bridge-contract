// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/AccessControlDefaultAdminRulesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Bridge.sol";
import "../libraries/Quotes.sol";
import "../libraries/SignatureValidator.sol";
import "../libraries/BtcUtils.sol";
import "../libraries/FlyoverModule.sol";
import "../liquidity-provider-contract/LiquidityProviderContract.sol";

contract PegoutContract is Initializable, ReentrancyGuardUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    uint constant public PAY_TO_ADDRESS_OUTPUT = 0;
    uint constant public QUOTE_HASH_OUTPUT = 1;
    
    struct PegoutRecord {
        uint256 depositTimestamp;
        bool completed;
    }

    event PegOutRefunded(bytes32 quoteHash);
    event PegOutDeposit(
        bytes32 quoteHash, address indexed sender, 
        uint256 indexed amount, uint256 indexed timestamp
    );
    event PegOutUserRefunded(bytes32 quoteHash, uint256 value, address userAddress);

    Bridge public bridge;
    LiquidityProviderContract private liquidityProviderContract;

    mapping(bytes32 => PegoutRecord) private pegoutRegistry;
    mapping(bytes32 => Quotes.PegOutQuote) private registeredPegoutQuotes;

    bool private mainnet;
    uint private btcBlockTime;

    // there isn't one LBC anymore so this contract needs to know
    // which address are using LPs to hash the quotes
    address private providerInterfaceAddress;

    modifier onlyLP() {
        require(liquidityProviderContract.isRegisteredForPegout(tx.origin), "LBC001");
        _;
    }

    /**
        @param _bridgeAddress The address of the bridge contract
        @param _liquidityProviderContract The address of the liquidity provider contract
        @param _btcBlockTime aprox minning time on btc network in seconds
        @param _mainnet the current network where contract is being deployed
     */
    function initialize(
        address payable _bridgeAddress,
        address payable _liquidityProviderContract,
        uint _btcBlockTime,
        bool _mainnet
    ) external initializer {
        __AccessControlDefaultAdminRules_init(30 minutes, msg.sender);
        bridge = Bridge(_bridgeAddress);
        liquidityProviderContract = LiquidityProviderContract(_liquidityProviderContract);
        btcBlockTime = _btcBlockTime;
        mainnet = _mainnet;
    }


    function getRegisteredPegOutQuote(
        bytes32 quoteHash
    ) external view returns (Quotes.PegOutQuote memory) {
        return registeredPegoutQuotes[quoteHash];
    }

    function isPegOutQuoteCompleted(bytes32 quoteHash) external view returns (bool) {
        return pegoutRegistry[quoteHash].completed;
    }

    function refundPegOut(
        bytes32 quoteHash,
        bytes calldata btcTx,
        bytes32 btcBlockHeaderHash,
        uint256 partialMerkleTree,
        bytes32[] calldata merkleBranchHashes
    ) external onlyRole(FlyoverModule.MODULE_ROLE) nonReentrant onlyLP {
        require(pegoutRegistry[quoteHash].completed == false, "LBC064");
        Quotes.PegOutQuote storage quote = registeredPegoutQuotes[quoteHash];
        require(quote.lbcAddress != address(0), "LBC042");
        BtcUtils.TxRawOutput[] memory outputs = BtcUtils.getOutputs(btcTx);
        bytes32 txQuoteHash = abi.decode(BtcUtils.parseOpReturnOuput(outputs[QUOTE_HASH_OUTPUT].pkScript), (bytes32));
        require(quoteHash == txQuoteHash, "LBC069");
        require(tx.origin == quote.lpRskAddress, "LBC048");
        require(
            bridge.getBtcTransactionConfirmations(
                BtcUtils.hashBtcTx(btcTx),
                btcBlockHeaderHash,
                partialMerkleTree,
                merkleBranchHashes
            ) >= int(uint256(quote.transferConfirmations)),
            "LBC049"
        );
        require(quote.value <= outputs[PAY_TO_ADDRESS_OUTPUT].value * (10**10), "LBC067"); // satoshi to wei
        bytes memory btcTxDestination = BtcUtils.parsePayToAddressScript(outputs[PAY_TO_ADDRESS_OUTPUT]
            .pkScript, mainnet);
        require(keccak256(quote.deposityAddress) == keccak256(btcTxDestination), "LBC068");

        if (
            shouldPenalizePegOutLP(
                quote,
                txQuoteHash,
                btcBlockHeaderHash
            )
        ) {
            liquidityProviderContract.penalizeForPegout(quote, quoteHash);
        }

        (bool sent,) = quote.lpRskAddress.call{
                value: quote.value + quote.callFee
            }("");
        require(sent, "LBC050");

        delete registeredPegoutQuotes[txQuoteHash];
        pegoutRegistry[txQuoteHash].completed = true;
        emit PegOutRefunded(txQuoteHash);
    }

    function depositPegout(
        Quotes.PegOutQuote calldata quote,
        bytes calldata signature
    ) external payable onlyRole(FlyoverModule.MODULE_ROLE) {
        require(liquidityProviderContract.isRegisteredForPegout(quote.lpRskAddress), "LBC037");
        require(quote.value + quote.callFee <= msg.value, "LBC063");
        require(block.timestamp <= quote.depositDateLimit, "LBC065");
        require(block.timestamp <= quote.expireDate, "LBC046");
        require(block.number <= quote.expireBlock, "LBC047");
        bytes32 quoteHash = hashPegoutQuote(quote);
        require(
            SignatureValidator.verify(quote.lpRskAddress, quoteHash, signature),
            "LBC029"
        );

        Quotes.PegOutQuote storage registeredQuote = registeredPegoutQuotes[quoteHash];

        require(pegoutRegistry[quoteHash].completed == false, "LBC064");
        require(registeredQuote.lbcAddress == address(0), "LBC028");
        registeredPegoutQuotes[quoteHash] = quote;
        pegoutRegistry[quoteHash].depositTimestamp = block.timestamp;
        emit PegOutDeposit(quoteHash, tx.origin, msg.value, block.timestamp);
    }

    function refundUserPegOut(
        bytes32 quoteHash
    ) external onlyRole(FlyoverModule.MODULE_ROLE) nonReentrant {
        Quotes.PegOutQuote storage quote = registeredPegoutQuotes[quoteHash];

        require(quote.lbcAddress != address(0), "LBC042");
        require(
            block.timestamp > quote.expireDate &&
            block.number > quote.expireBlock,
            "LBC041"
        );

        uint valueToTransfer = quote.value + quote.callFee;

        liquidityProviderContract.penalizeForPegout(quote, quoteHash);

        emit PegOutUserRefunded(
            quoteHash,
            valueToTransfer,
            quote.rskRefundAddress
        );

        delete registeredPegoutQuotes[quoteHash];
        pegoutRegistry[quoteHash].completed = true;

        (bool sent,) = quote.rskRefundAddress.call{value: valueToTransfer}("");
        require(sent, "LBC044");
    }

    function hashPegoutQuote(
        Quotes.PegOutQuote calldata quote
    ) public view onlyRole(FlyoverModule.MODULE_ROLE) returns (bytes32) {
        return validateAndHashPegOutQuote(quote);
    }

    function shouldPenalizePegOutLP(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash,
        bytes32 blockHash
    ) private view returns (bool) {
        bytes memory firstConfirmationHeader = bridge.getBtcBlockchainBlockHeaderByHash(blockHash);
        require(firstConfirmationHeader.length > 0, "LBC059");

        uint256 firstConfirmationTimestamp = BtcUtils.getBtcBlockTimestamp(firstConfirmationHeader);

        // penalize if the transfer was not made on time
        if (firstConfirmationTimestamp > pegoutRegistry[quoteHash].depositTimestamp +
            quote.transferTime + btcBlockTime) {
            return true;
        }

        // penalize if LP is refunding after expiration
        if (block.timestamp > quote.expireDate || block.number > quote.expireBlock) {
            return true;
        }

        return false;
    }

    function validateAndHashPegOutQuote(
        Quotes.PegOutQuote calldata quote
    ) private view returns (bytes32) {
        require(providerInterfaceAddress == quote.lbcAddress, "LBC056");

        return keccak256(Quotes.encodePegOutQuote(quote));
    }

    function getProviderInterfaceAddress() external view returns (address) {
        require(msg.sender == owner(), "LBC072");
        return providerInterfaceAddress;
    }

    function setProviderInterfaceAddress(address _providerInterfaceAddress) external {
        require(msg.sender == owner(), "LBC072");
        providerInterfaceAddress = _providerInterfaceAddress;
    }
}