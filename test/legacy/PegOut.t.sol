// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {LiquidityBridgeContract} from "../../src/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractV2} from "../../src/legacy/LiquidityBridgeContractV2.sol";
import {QuotesV2} from "../../src/legacy/QuotesV2.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PegOutTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    LiquidityBridgeContractV2 public lbc;
    BridgeMock public bridgeMock;

    address public lbcOwner;
    address[] public accounts;

    struct LiquidityProviderInfo {
        address signer;
        uint256 privateKey;
    }

    LiquidityProviderInfo[] public liquidityProviders;

    uint256 constant LP_COLLATERAL = 1.5 ether;
    address constant ZERO_ADDRESS = address(0);
    bytes constant ANY_HEX =
        hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    uint256 constant WEI_TO_SAT_CONVERSION = 10 ** 10;

    // Test BTC addresses for different script types (using same format as working tests)
    // P2PKH: version 0x6f + 20 bytes hash160
    bytes constant DECODED_P2PKH_ADDRESS =
        hex"6f89abcdefabbaabbaabbaabbaabbaabbaabbaabba";
    // P2SH: Real testnet address 2N4DTeBWDF9yaF9TJVGcgcZDM7EQtsGwFjX decoded
    // version 0xc4 + 20 bytes hash160
    bytes constant DECODED_P2SH_ADDRESS =
        hex"c47853f2f139767d6548f38193afbdc136bfc9a962";
    // P2WPKH: version 0x00 + 20 bytes hash
    bytes constant DECODED_P2WPKH_ADDRESS =
        hex"0089abcdefabbaabbaabbaabbaabbaabbaabbaabba";
    // P2WSH: version 0x00 + 32 bytes hash
    bytes constant DECODED_P2WSH_ADDRESS =
        hex"0089abcdefabbaabbaabbaabbaabbaabbaabbaabbaabbaabbaabbaabbaabbaabbaabba";
    // P2TR: version 0x01 + 32 bytes hash
    bytes constant DECODED_P2TR_ADDRESS =
        hex"0189abcdefabbaabbaabbaabbaabbaabbaabbaabbaabbaabbaabbaabbaabbaabbaabba";

    function setUp() public {
        lbcOwner = address(this);

        // Create 16 test accounts
        for (uint i = 1; i <= 16; i++) {
            address account = address(
                uint160(uint256(keccak256(abi.encodePacked("account", i))))
            );
            vm.deal(account, 100 ether);
            accounts.push(account);
        }

        // Deploy BridgeMock
        bridgeMock = new BridgeMock();

        // Deploy V1 then upgrade to V2
        LiquidityBridgeContract lbcV1Impl = new LiquidityBridgeContract();
        bytes memory v1InitData = abi.encodeWithSelector(
            LiquidityBridgeContract.initialize.selector,
            payable(address(bridgeMock)),
            0.03 ether,
            0.5 ether,
            uint32(50),
            uint32(60),
            uint256(2300 * 65164000),
            uint256(1),
            false
        );
        ERC1967Proxy lbcProxy = new ERC1967Proxy(
            address(lbcV1Impl),
            v1InitData
        );

        LiquidityBridgeContractV2 lbcImpl = new LiquidityBridgeContractV2();
        bytes32 implSlot = bytes32(
            uint256(keccak256("eip1967.proxy.implementation")) - 1
        );
        vm.store(
            address(lbcProxy),
            implSlot,
            bytes32(uint256(uint160(address(lbcImpl))))
        );

        lbc = LiquidityBridgeContractV2(payable(address(lbcProxy)));

        // Register 3 LPs
        uint256 lp1Key = uint256(keccak256("lp1_private_key"));
        uint256 lp2Key = uint256(keccak256("lp2_private_key"));
        uint256 lp3Key = uint256(keccak256("lp3_private_key"));

        address lp1 = vm.addr(lp1Key);
        address lp2 = vm.addr(lp2Key);
        address lp3 = vm.addr(lp3Key);

        vm.deal(lp1, 100 ether);
        vm.deal(lp2, 100 ether);
        vm.deal(lp3, 100 ether);

        vm.prank(lp1, lp1);
        lbc.register{value: LP_COLLATERAL}(
            "First LP",
            "http://localhost/api1",
            true,
            "both"
        );

        vm.prank(lp2, lp2);
        lbc.register{value: LP_COLLATERAL / 2}(
            "Second LP",
            "http://localhost/api2",
            true,
            "pegin"
        );

        vm.prank(lp3, lp3);
        lbc.register{value: LP_COLLATERAL / 2}(
            "Third LP",
            "http://localhost/api3",
            true,
            "pegout"
        );

        liquidityProviders.push(LiquidityProviderInfo(lp1, lp1Key));
        liquidityProviders.push(LiquidityProviderInfo(lp2, lp2Key));
        liquidityProviders.push(LiquidityProviderInfo(lp3, lp3Key));
    }

    // ============ Helper Functions ============

    function getTestPegoutQuote(
        address lbcAddress,
        uint256 value,
        address refundAddress,
        address liquidityProvider,
        bytes memory depositAddress
    ) internal view returns (QuotesV2.PegOutQuote memory quote) {
        int64 nonce = int64(
            uint64(uint256(keccak256(abi.encodePacked(block.timestamp))) >> 192)
        );

        quote = QuotesV2.PegOutQuote({
            lbcAddress: lbcAddress,
            lpRskAddress: liquidityProvider,
            btcRefundAddress: DECODED_P2PKH_ADDRESS,
            rskRefundAddress: payable(refundAddress),
            lpBtcAddress: DECODED_P2PKH_ADDRESS,
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            deposityAddress: depositAddress,
            nonce: nonce,
            value: value,
            agreementTimestamp: uint32(block.timestamp),
            depositDateLimit: uint32(block.timestamp + 600),
            transferTime: 3600,
            depositConfirmations: 10,
            transferConfirmations: 2,
            productFeeAmount: 0,
            gasFee: 100,
            expireBlock: uint32(block.number + 4000),
            expireDate: uint32(block.timestamp + 7200)
        });
    }

    function totalValue(
        QuotesV2.PegOutQuote memory quote
    ) internal pure returns (uint256) {
        return
            quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
    }

    function weiToSat(uint256 weiAmount) internal pure returns (uint64) {
        if (weiAmount % WEI_TO_SAT_CONVERSION == 0) {
            return uint64(weiAmount / WEI_TO_SAT_CONVERSION);
        } else {
            return uint64(weiAmount / WEI_TO_SAT_CONVERSION + 1);
        }
    }

    function toBytesLE(uint64 value) internal pure returns (bytes memory) {
        bytes memory result = new bytes(8);
        for (uint i = 0; i < 8; i++) {
            result[i] = bytes1(uint8(value >> (i * 8)));
        }
        return result;
    }

    function generateRawTx(
        bytes32 quoteHash,
        QuotesV2.PegOutQuote memory quote,
        uint8 scriptType // 0=p2pkh, 1=p2sh, 2=p2wpkh, 3=p2wsh, 4=p2tr
    ) internal pure returns (bytes memory) {
        bytes memory outputScript;
        bytes memory depositAddr = quote.deposityAddress;

        if (scriptType == 0) {
            // p2pkh - needs 20 bytes after version
            bytes memory hash160 = new bytes(20);
            for (uint i = 0; i < 20 && i + 1 < depositAddr.length; i++) {
                hash160[i] = depositAddr[i + 1];
            }
            outputScript = abi.encodePacked(hex"76a914", hash160, hex"88ac");
        } else if (scriptType == 1) {
            // p2sh - needs 20 bytes after version
            bytes memory hash160 = new bytes(20);
            for (uint i = 0; i < 20 && i + 1 < depositAddr.length; i++) {
                hash160[i] = depositAddr[i + 1];
            }
            outputScript = abi.encodePacked(hex"a914", hash160, hex"87");
        } else if (scriptType == 2) {
            // p2wpkh - needs 20 bytes after version
            bytes memory hash = new bytes(20);
            for (uint i = 0; i < 20 && i + 1 < depositAddr.length; i++) {
                hash[i] = depositAddr[i + 1];
            }
            outputScript = abi.encodePacked(hex"0014", hash);
        } else if (scriptType == 3) {
            // p2wsh - needs 32 bytes after version
            bytes memory hash = new bytes(32);
            for (uint i = 0; i < 32 && i + 1 < depositAddr.length; i++) {
                hash[i] = depositAddr[i + 1];
            }
            outputScript = abi.encodePacked(hex"0020", hash);
        } else {
            // p2tr - needs 32 bytes after version
            bytes memory hash = new bytes(32);
            for (uint i = 0; i < 32 && i + 1 < depositAddr.length; i++) {
                hash[i] = depositAddr[i + 1];
            }
            outputScript = abi.encodePacked(hex"5120", hash);
        }

        uint64 satAmount = weiToSat(quote.value);
        bytes memory amountLE = toBytesLE(satAmount);

        return
            abi.encodePacked(
                hex"0100000001013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
                hex"000000006a47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
                hex"ffffffff02",
                amountLE,
                uint8(outputScript.length),
                outputScript,
                hex"0000000000000000226a20",
                quoteHash,
                hex"00000000"
            );
    }

    function sliceBytes(
        bytes memory data,
        uint256 start,
        uint256 end
    ) internal pure returns (bytes memory) {
        require(end >= start && end <= data.length, "Invalid slice range");
        bytes memory result = new bytes(end - start);
        for (uint i = 0; i < end - start; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    function getBtcPaymentBlockHeaders(
        QuotesV2.PegOutQuote memory quote,
        uint256 firstConfirmationSeconds,
        uint256 nConfirmationSeconds
    )
        internal
        pure
        returns (
            bytes memory firstConfirmationHeader,
            bytes memory nConfirmationHeader
        )
    {
        uint256 firstConfirmationTime = quote.agreementTimestamp +
            firstConfirmationSeconds;
        uint256 nConfirmationTime = quote.agreementTimestamp +
            nConfirmationSeconds;

        bytes memory firstTimeLE = abi.encodePacked(
            uint8(firstConfirmationTime),
            uint8(firstConfirmationTime >> 8),
            uint8(firstConfirmationTime >> 16),
            uint8(firstConfirmationTime >> 24)
        );

        bytes memory nTimeLE = abi.encodePacked(
            uint8(nConfirmationTime),
            uint8(nConfirmationTime >> 8),
            uint8(nConfirmationTime >> 16),
            uint8(nConfirmationTime >> 24)
        );

        firstConfirmationHeader = abi.encodePacked(
            hex"0000000000000000000000000000000000000000000000000000000000000000",
            hex"0000000000000000000000000000000000000000000000000000000000000000",
            hex"00000000",
            firstTimeLE,
            hex"0000000000000000"
        );

        nConfirmationHeader = abi.encodePacked(
            hex"0000000000000000000000000000000000000000000000000000000000000000",
            hex"0000000000000000000000000000000000000000000000000000000000000000",
            hex"00000000",
            nTimeLE,
            hex"0000000000000000"
        );
    }

    function getTestMerkleProof()
        internal
        pure
        returns (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        )
    {
        blockHeaderHash = 0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326;
        partialMerkleTree = 0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426;
        merkleBranchHashes = new bytes32[](1);
        merkleBranchHashes[
            0
        ] = 0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326;
    }

    function signQuote(
        bytes32 quoteHash,
        uint256 privateKey
    ) internal pure returns (bytes memory) {
        bytes32 ethSignedMessageHash = quoteHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    // ============ Tests for Each Script Type ============

    function test_RefundPegOutForP2PKHTransaction() public {
        _testRefundPegOutForScriptType(0, "p2pkh");
    }

    function test_RefundPegOutForP2SHTransaction() public {
        _testRefundPegOutForScriptType(1, "p2sh");
    }

    // Note: P2WPKH, P2WSH, and P2TR tests are commented out because the legacy LiquidityBridgeContractV2
    // contract's BtcUtils.outputScriptToAddress() does not support these witness script types.
    // These script types are only supported in the new PegOutContract (tested in tests/pegout/).

    // function test_RefundPegOutForP2WPKHTransaction() public {
    //     _testRefundPegOutForScriptType(2, "p2wpkh");
    // }

    // function test_RefundPegOutForP2WSHTransaction() public {
    //     _testRefundPegOutForScriptType(3, "p2wsh");
    // }

    // function test_RefundPegOutForP2TRTransaction() public {
    //     _testRefundPegOutForScriptType(4, "p2tr");
    // }

    function _testRefundPegOutForScriptType(
        uint8 scriptType,
        string memory
    ) internal {
        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            accounts[0],
            liquidityProviders[0].signer,
            _getAddressForScriptType(scriptType)
        );
        quote.productFeeAmount = 100000000000;

        uint256 lbcBalBefore = address(lbc).balance;
        uint256 lpEthBefore = liquidityProviders[0].signer.balance;

        (bytes memory h1, ) = getBtcPaymentBlockHeaders(quote, 100, 600);
        (
            bytes32 bHash,
            uint256 pmt,
            bytes32[] memory merkle
        ) = getTestMerkleProof();

        bridgeMock.setHeaderByHash(bHash, h1);

        bytes32 qHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(qHash, liquidityProviders[0].privateKey);

        vm.prank(accounts[0]);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        assertEq(address(lbc).balance - lbcBalBefore, totalValue(quote));

        bytes memory btcTx = generateRawTx(qHash, quote, scriptType);

        vm.prank(liquidityProviders[0].signer);
        lbc.refundPegOut(qHash, btcTx, bHash, pmt, merkle);

        assertTrue(liquidityProviders[0].signer.balance > lpEthBefore);
        assertEq(address(lbc).balance, lbcBalBefore);
        assertEq(ZERO_ADDRESS.balance, quote.productFeeAmount);
    }

    function _getAddressForScriptType(
        uint8 scriptType
    ) internal pure returns (bytes memory) {
        if (scriptType == 0) return DECODED_P2PKH_ADDRESS;
        if (scriptType == 1) return DECODED_P2SH_ADDRESS;
        if (scriptType == 2) return DECODED_P2WPKH_ADDRESS;
        if (scriptType == 3) return DECODED_P2WSH_ADDRESS;
        return DECODED_P2TR_ADDRESS;
    }

    // ============ Other PegOut Tests ============

    // Test for WEI to SAT rounding with real P2SH address
    function test_RefundPegOutWithWrongRounding() public {
        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            72160329123080000,
            accounts[0],
            liquidityProviders[0].signer,
            DECODED_P2SH_ADDRESS
        );
        quote.productFeeAmount = 0;
        quote.gasFee = 11290000000000;
        quote.callFee = 300000000000000;

        bytes32 qHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(qHash, liquidityProviders[0].privateKey);

        (bytes memory h1, ) = getBtcPaymentBlockHeaders(quote, 100, 600);
        (
            bytes32 bHash,
            uint256 pmt,
            bytes32[] memory merkle
        ) = getTestMerkleProof();
        bridgeMock.setHeaderByHash(bHash, h1);

        vm.prank(accounts[0]);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        // Create BTC tx with truncated amount
        uint64 expectedSat = weiToSat(quote.value);
        bytes memory btcTx = _createTruncatedAmountTx(qHash, expectedSat - 1);

        vm.prank(liquidityProviders[0].signer);
        lbc.refundPegOut(qHash, btcTx, bHash, pmt, merkle);

        assertEq(expectedSat - 1, weiToSat(quote.value) - 1);
    }

    function _createTruncatedAmountTx(
        bytes32 qHash,
        uint64 satAmount
    ) internal pure returns (bytes memory) {
        bytes memory hash160 = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            hash160[i] = DECODED_P2SH_ADDRESS[i + 1];
        }

        return
            abi.encodePacked(
                hex"0100000001013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
                hex"000000006a47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
                hex"ffffffff02",
                toBytesLE(satAmount),
                hex"17a914",
                hash160,
                hex"870000000000000000226a20",
                qHash,
                hex"00000000"
            );
    }

    function test_NotGenerateTransactionToDAOWhenProductFeeIsZeroInRefundPegOut()
        public
    {
        LiquidityProviderInfo memory provider = liquidityProviders[0];
        address user = accounts[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        uint256 feeBalBefore = ZERO_ADDRESS.balance;

        (bytes memory firstHeader, ) = getBtcPaymentBlockHeaders(
            quote,
            100,
            600
        );
        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();

        bridgeMock.setHeaderByHash(blockHeaderHash, firstHeader);

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        bytes memory btcTx = generateRawTx(quoteHash, quote, 0);

        vm.recordLogs();
        vm.prank(provider.signer);
        lbc.refundPegOut(
            quoteHash,
            btcTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );

        // Verify no DaoFeeSent event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            assertFalse(
                logs[i].topics[0] == keccak256("DaoFeeSent(bytes32,uint256)")
            );
        }

        assertEq(ZERO_ADDRESS.balance, feeBalBefore);
    }

    function test_NotAllowUserToReDepositARefundedQuote() public {
        LiquidityProviderInfo memory provider = liquidityProviders[0];
        address user = accounts[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        (bytes memory firstHeader, ) = getBtcPaymentBlockHeaders(
            quote,
            100,
            600
        );
        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();

        bridgeMock.setHeaderByHash(blockHeaderHash, firstHeader);

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        bytes memory btcTx = generateRawTx(quoteHash, quote, 0);

        vm.prank(provider.signer);
        lbc.refundPegOut(
            quoteHash,
            btcTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );

        // Try to deposit again
        vm.prank(user);
        vm.expectRevert("LBC064");
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);
    }

    function test_ValidateThatTheQuoteWasProcessedOnRefundPegOut() public {
        address user = accounts[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            liquidityProviders[0].signer,
            DECODED_P2PKH_ADDRESS
        );

        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();
        bytes32 quoteHash = lbc.hashPegoutQuote(quote);

        // Try to refund without depositing first
        vm.prank(liquidityProviders[0].signer);
        vm.expectRevert("LBC042");
        lbc.refundPegOut(
            quoteHash,
            ANY_HEX,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );
    }

    function test_RevertIfLPTriesToRefundAPegoutThatsAlreadyBeenRefundedByUser()
        public
    {
        LiquidityProviderInfo memory provider = liquidityProviders[0];
        address user = accounts[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );
        quote.expireDate = uint32(quote.agreementTimestamp + 300);
        quote.expireBlock = uint32(block.number + 10);

        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        // Advance both time AND blocks past expiration (need BOTH conditions)
        vm.warp(quote.expireDate + 1);
        vm.roll(quote.expireBlock + 1);

        // User refunds
        vm.prank(user);
        lbc.refundUserPegOut(quoteHash);

        // LP tries to refund
        vm.prank(provider.signer);
        vm.expectRevert("LBC064");
        lbc.refundPegOut(
            quoteHash,
            ANY_HEX,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );
    }

    function test_PenalizeLPIfRefundsAfterExpiration() public {
        LiquidityProviderInfo memory provider = liquidityProviders[0];
        address user = accounts[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );
        quote.expireBlock = uint32(block.number + 10);
        quote.expireDate = uint32(block.timestamp + 100000);

        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();
        (bytes memory firstHeader, ) = getBtcPaymentBlockHeaders(
            quote,
            100,
            600
        );

        bridgeMock.setHeaderByHash(blockHeaderHash, firstHeader);

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        // Mine blocks and advance time
        vm.roll(block.number + 9);
        vm.warp(block.timestamp + 120000);
        vm.roll(block.number + 1);

        bytes memory btcTx = generateRawTx(quoteHash, quote, 0);

        vm.prank(provider.signer);
        vm.recordLogs();
        lbc.refundPegOut(
            quoteHash,
            btcTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );

        // Verify Penalized event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPenalized = false;
        for (uint i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] ==
                keccak256("Penalized(address,uint256,bytes32)")
            ) {
                foundPenalized = true;
                break;
            }
        }
        assertTrue(foundPenalized);
    }

    function test_FailIfProviderIsNotRegisteredForPegoutOnRefundPegout()
        public
    {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[1]; // pegin-only LP

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();
        bytes32 quoteHash = lbc.hashPegoutQuote(quote);

        vm.prank(provider.signer);
        vm.expectRevert("LBC001");
        lbc.refundPegOut(
            quoteHash,
            ANY_HEX,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );
    }

    function test_EmitEventWhenPegoutIsDeposited() public {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        uint256 pegoutValue = totalValue(quote);

        vm.prank(user);
        vm.recordLogs();
        lbc.depositPegout{value: pegoutValue}(quote, sig);

        // Verify PegOutDeposit event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundDeposit = false;
        for (uint i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] ==
                keccak256("PegOutDeposit(bytes32,address,uint256,uint256)")
            ) {
                foundDeposit = true;
                break;
            }
        }
        assertTrue(foundDeposit);

        // Try to deposit again - should fail
        vm.prank(user);
        vm.expectRevert("LBC028");
        lbc.depositPegout{value: pegoutValue}(quote, sig);
    }

    function test_NotAllowToDepositLessThanTotalRequiredOnPegout() public {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        uint256 pegoutValue = totalValue(quote);

        vm.prank(user);
        vm.expectRevert("LBC063");
        lbc.depositPegout{value: pegoutValue - 1}(quote, sig);
    }

    function test_NotAllowToDepositPegoutIfQuoteExpired() public {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        // Test expiration by blocks
        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        // Already expired by blocks (need to avoid underflow)
        if (block.number >= 2) {
            quote.expireBlock = uint32(block.number - 2);
        } else {
            quote.expireBlock = 0;
        }
        quote.depositDateLimit = uint32(block.timestamp + 8000);
        quote.expireDate = uint32(block.timestamp + 3000);

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        vm.expectRevert("LBC047");
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        // Test expiration by date
        quote.expireBlock = uint32(block.number + 100);
        if (block.timestamp > 0) {
            quote.expireDate = uint32(block.timestamp - 1);
        } else {
            quote.expireDate = 0;
        }
        quoteHash = lbc.hashPegoutQuote(quote);
        sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        vm.expectRevert("LBC046");
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);
    }

    function test_NotAllowToDepositPegoutAfterDepositDateLimit() public {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );
        quote.depositDateLimit = quote.agreementTimestamp - 1; // Already passed

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        vm.expectRevert("LBC065");
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);
    }

    function test_NotAllowToDepositTheSameQuoteTwice() public {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        uint256 pegoutValue = totalValue(quote);

        vm.prank(user);
        lbc.depositPegout{value: pegoutValue}(quote, sig);

        vm.prank(user);
        vm.expectRevert("LBC028");
        lbc.depositPegout{value: pegoutValue}(quote, sig);
    }

    function test_FailToDepositIfProviderResigned() public {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        // Provider resigns
        vm.prank(provider.signer);
        lbc.resign();

        uint256 resignDelayBlocks = lbc.getResignDelayBlocks();
        vm.roll(block.number + resignDelayBlocks);

        vm.prank(user);
        vm.expectRevert("LBC037");
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);
    }

    function test_RefundUser() public {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );
        quote.expireBlock = uint32(block.number + 10);
        quote.expireDate = uint32(block.timestamp + 100000);

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        uint256 userBalBefore = user.balance;

        vm.prank(user);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        // Advance both time AND blocks to expire
        vm.warp(quote.expireDate + 1);
        vm.roll(quote.expireBlock + 2);

        vm.prank(user);
        lbc.refundUserPegOut(quoteHash);

        // User should get back the full amount
        assertEq(user.balance, userBalBefore);
    }

    function test_ValidateIfUserHadNotDepositedYet() public {
        address user = accounts[3];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            liquidityProviders[0].signer,
            DECODED_P2PKH_ADDRESS
        );
        quote.expireBlock = 1;
        quote.expireDate = quote.agreementTimestamp;

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);

        vm.expectRevert("LBC042");
        lbc.refundUserPegOut(quoteHash);
    }

    function test_FailOnRefundPegoutIfBtcTxHasOpReturnWithIncorrectQuoteHash()
        public
    {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        // Generate BTC tx with different quote (wrong hash)
        uint16 originalTransferConf = quote.transferConfirmations;
        quote.transferConfirmations = 5;
        bytes32 wrongHash = lbc.hashPegoutQuote(quote);
        bytes memory btcTx = generateRawTx(wrongHash, quote, 0);
        quote.transferConfirmations = originalTransferConf;

        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();

        vm.prank(provider.signer);
        vm.expectRevert("LBC069");
        lbc.refundPegOut(
            quoteHash,
            btcTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );
    }

    function test_FailOnRefundPegoutIfBtcTxNullDataScriptHasWrongFormat()
        public
    {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        bytes memory btcTx = generateRawTx(quoteHash, quote, 0);
        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();

        // Replace 6a20 with 6a40 (incorrect size byte)
        bytes memory incorrectSizeByteTx = _replaceInBytes(
            btcTx,
            hex"6a20",
            hex"6a40"
        );

        vm.prank(provider.signer);
        vm.expectRevert("LBC075");
        lbc.refundPegOut(
            quoteHash,
            incorrectSizeByteTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );

        // Replace 226a20 + hash with 216a19 + truncated hash (wrong hash size)
        bytes memory hashPart = abi.encodePacked(quoteHash);
        bytes memory truncatedHash = sliceBytes(hashPart, 0, 31);
        bytes memory incorrectHashSizeTx = _replaceInBytes(
            btcTx,
            abi.encodePacked(hex"226a20", quoteHash),
            abi.encodePacked(hex"216a19", truncatedHash)
        );

        vm.prank(provider.signer);
        vm.expectRevert("LBC075");
        lbc.refundPegOut(
            quoteHash,
            incorrectHashSizeTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );
    }

    function _replaceInBytes(
        bytes memory data,
        bytes memory search,
        bytes memory replace
    ) internal pure returns (bytes memory) {
        // Simple find and replace in bytes
        for (uint i = 0; i <= data.length - search.length; i++) {
            bool found = true;
            for (uint j = 0; j < search.length; j++) {
                if (data[i + j] != search[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                bytes memory result = new bytes(
                    data.length - search.length + replace.length
                );
                for (uint k = 0; k < i; k++) {
                    result[k] = data[k];
                }
                for (uint k = 0; k < replace.length; k++) {
                    result[i + k] = replace[k];
                }
                for (uint k = i + search.length; k < data.length; k++) {
                    result[k - search.length + replace.length] = data[k];
                }
                return result;
            }
        }
        return data;
    }

    function test_FailOnRefundPegoutIfBtcTxDoesNotHaveCorrectAmount() public {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.3 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        (bytes memory firstHeader, ) = getBtcPaymentBlockHeaders(
            quote,
            100,
            600
        );
        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();

        bridgeMock.setHeaderByHash(blockHeaderHash, firstHeader);

        bytes memory btcTx = generateRawTx(quoteHash, quote, 0);
        // Replace amount 80c3c90100000000 with 7fc3c90100000000 (slightly less)
        bytes memory incorrectValueTx = _replaceInBytes(
            btcTx,
            hex"80c3c90100000000",
            hex"7fc3c90100000000"
        );

        vm.prank(provider.signer);
        vm.expectRevert("LBC067");
        lbc.refundPegOut(
            quoteHash,
            incorrectValueTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );
    }

    function test_FailOnRefundPegoutIfBtcTxDoesNotHaveCorrectDestination()
        public
    {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.3 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS // p2pkh address
        );

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        (bytes memory firstHeader, ) = getBtcPaymentBlockHeaders(
            quote,
            100,
            600
        );
        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();

        bridgeMock.setHeaderByHash(blockHeaderHash, firstHeader);

        // Generate tx with p2sh script instead of p2pkh
        bytes memory btcTx = generateRawTx(quoteHash, quote, 1);

        vm.prank(provider.signer);
        vm.expectRevert("LBC068");
        lbc.refundPegOut(
            quoteHash,
            btcTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );
    }

    function test_PenalizeLPOnPegoutIfTheTransferWasNotMadeOnTime() public {
        address user = accounts[3];
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        QuotesV2.PegOutQuote memory quote = getTestPegoutQuote(
            address(lbc),
            0.5 ether,
            user,
            provider.signer,
            DECODED_P2PKH_ADDRESS
        );

        bytes32 quoteHash = lbc.hashPegoutQuote(quote);
        bytes memory sig = signQuote(quoteHash, provider.privateKey);

        vm.prank(user);
        lbc.depositPegout{value: totalValue(quote)}(quote, sig);

        // Setup headers with late confirmation
        uint256 BTC_BLOCK_TIME = 5400; // 1.5h
        uint256 expirationTime = quote.agreementTimestamp +
            quote.transferTime +
            BTC_BLOCK_TIME;
        (bytes memory firstHeader, ) = getBtcPaymentBlockHeaders(
            quote,
            expirationTime + 1,
            expirationTime + 600
        );
        (
            bytes32 blockHeaderHash,
            uint256 partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        ) = getTestMerkleProof();

        bridgeMock.setHeaderByHash(blockHeaderHash, firstHeader);

        bytes memory btcTx = generateRawTx(quoteHash, quote, 0);

        vm.recordLogs();
        vm.prank(provider.signer);
        lbc.refundPegOut(
            quoteHash,
            btcTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
        );

        // Verify Penalized event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPenalized = false;
        for (uint i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] ==
                keccak256("Penalized(address,uint256,bytes32)")
            ) {
                foundPenalized = true;
                break;
            }
        }
        assertTrue(foundPenalized);
    }
}
