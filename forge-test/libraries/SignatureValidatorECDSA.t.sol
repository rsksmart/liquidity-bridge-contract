// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {LiquidityBridgeContract} from "../../contracts/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractV2} from "../../contracts/legacy/LiquidityBridgeContractV2.sol";
import {QuotesV2} from "../../contracts/legacy/QuotesV2.sol";
import {BridgeMock} from "../../contracts/test-contracts/BridgeMock.sol";
import {ECDSAError} from "../../contracts/test-contracts/ECDSAError.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title LBC Signature Malleability Defense Test
/// @notice Tests that the LBC rejects malleable ECDSA signatures (high-s values)
contract SignatureValidatorECDSATest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    LiquidityBridgeContractV2 public lbc;
    BridgeMock public bridgeMock;
    ECDSAError public ecdsaError;

    address public lp;
    uint256 public lpKey;
    address public user;

    uint256 constant LP_COLLATERAL = 1.5 ether;
    uint256 constant MIN_COLLATERAL_TEST = 0.03 ether;

    // secp256k1 curve order
    uint256 constant SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    // BTC address for pegout
    bytes constant DECODED_P2PKH_ADDRESS = hex"6f89abcdefabbaabbaabbaabbaabbaabbaabbaabba";

    function setUp() public {
        // Deploy BridgeMock
        bridgeMock = new BridgeMock();

        // Deploy V1 then upgrade to V2 (with real SignatureValidator library linked)
        LiquidityBridgeContract lbcV1Impl = new LiquidityBridgeContract();
        bytes memory v1InitData = abi.encodeWithSelector(
            LiquidityBridgeContract.initialize.selector,
            payable(address(bridgeMock)),
            MIN_COLLATERAL_TEST,
            0.5 ether,
            uint32(10),
            uint32(60),
            uint256(2300 * 65164000),
            uint256(900),
            false
        );
        ERC1967Proxy lbcProxy = new ERC1967Proxy(address(lbcV1Impl), v1InitData);

        // Upgrade to V2
        LiquidityBridgeContractV2 lbcImpl = new LiquidityBridgeContractV2();
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        vm.store(address(lbcProxy), implSlot, bytes32(uint256(uint160(address(lbcImpl)))));

        lbc = LiquidityBridgeContractV2(payable(address(lbcProxy)));

        // Create LP and user
        (lp, lpKey) = makeAddrAndKey("lp");
        user = makeAddr("user");

        vm.deal(lp, 100 ether);
        vm.deal(user, 100 ether);

        // Register LP with pegout support
        vm.prank(lp, lp);
        lbc.register{value: LP_COLLATERAL}("LP", "http://lp.local", true, "both");

        // Deploy ECDSAError for custom error matching
        ecdsaError = new ECDSAError();
    }

    function test_RevertsWithECDSAInvalidSignatureSWhenDepositPegoutGetsHighSSignature() public {
        // Create a pegout quote
        QuotesV2.PegOutQuote memory quote = QuotesV2.PegOutQuote({
            lbcAddress: address(lbc),
            lpRskAddress: lp,
            btcRefundAddress: DECODED_P2PKH_ADDRESS,
            rskRefundAddress: payable(user),
            lpBtcAddress: DECODED_P2PKH_ADDRESS,
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            deposityAddress: DECODED_P2PKH_ADDRESS,
            nonce: int64(uint64(block.timestamp)),
            value: 1 ether,
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

        uint256 quoteValue = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;

        // Hash the quote
        bytes32 quoteHash = lbc.hashPegoutQuote(quote);

        // Sign with low-s (normal signature)
        bytes32 ethSignedMessageHash = quoteHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(lpKey, ethSignedMessageHash);

        // Create malleable signature by flipping s value to high-s
        // s' = SECP256K1_N - s
        // v' = flip v (27 <-> 28)
        uint256 sPrime = SECP256K1_N - uint256(s);
        uint8 vPrime = v == 27 ? 28 : 27;

        bytes memory malleableSig = abi.encodePacked(r, bytes32(sPrime), vPrime);

        // Verify the signature is malleable (high-s)
        assertTrue(sPrime > SECP256K1_N / 2, "sPrime should be high-s");

        // Attempt to deposit with malleable signature - should revert
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                ECDSAError.ECDSAInvalidSignatureS.selector,
                bytes32(sPrime)
            )
        );
        lbc.depositPegout{value: quoteValue}(quote, malleableSig);
    }
}
