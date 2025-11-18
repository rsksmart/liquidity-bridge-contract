// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {LiquidityBridgeContractV2} from "../../src/legacy/LiquidityBridgeContractV2.sol";
import {QuotesV2} from "../../src/legacy/QuotesV2.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {SignatureValidator} from "../../src/libraries/SignatureValidator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract LiquidityTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    LiquidityBridgeContractV2 public lbcImpl;
    ERC1967Proxy public lbcProxy;
    LiquidityBridgeContractV2 public lbc;
    BridgeMock public bridgeMock;

    address public lbcOwner;
    address[] public accounts;

    // Liquidity providers with private keys for signing
    struct LiquidityProviderInfo {
        address signer;
        uint256 privateKey;
        string name;
        string apiBaseUrl;
        bool status;
        string providerType;
    }

    LiquidityProviderInfo[] public liquidityProviders;

    uint256 constant LP_COLLATERAL = 1.5 ether;

    // BTC address constants (decoded from base58check)
    bytes constant DECODED_TEST_FED_ADDRESS =
        hex"c39bc4b53918d6058134363d6e57e11a22f9e8fb";
    bytes constant DECODED_P2PKH_ZERO_ADDRESS_TESTNET =
        hex"6f0000000000000000000000000000000000000000";
    bytes constant DECODED_TEST_P2PKH_ADDRESS =
        hex"6f89abcdefabbaabbaabbaabbaabbaabbaabbaabba";

    function setUp() public {
        lbcOwner = address(this);

        // Create test accounts
        for (uint i = 1; i <= 16; i++) {
            address account = address(
                uint160(uint256(keccak256(abi.encodePacked("account", i))))
            );
            vm.deal(account, 100 ether);
            accounts.push(account);
        }

        // Deploy BridgeMock
        bridgeMock = new BridgeMock();

        // Deploy LiquidityBridgeContractV2
        lbcImpl = new LiquidityBridgeContractV2();
        bytes memory initData = abi.encodeWithSelector(
            LiquidityBridgeContractV2.initializeV2.selector
        );
        lbcProxy = new ERC1967Proxy(address(lbcImpl), initData);
        lbc = LiquidityBridgeContractV2(payable(address(lbcProxy)));

        // Create LPs with deterministic private keys for signing
        uint256 lp1Key = uint256(keccak256("lp1_private_key"));
        uint256 lp2Key = uint256(keccak256("lp2_private_key"));
        uint256 lp3Key = uint256(keccak256("lp3_private_key"));

        address lp1 = vm.addr(lp1Key);
        address lp2 = vm.addr(lp2Key);
        address lp3 = vm.addr(lp3Key);

        vm.deal(lp1, 100 ether);
        vm.deal(lp2, 100 ether);
        vm.deal(lp3, 100 ether);

        // Register 3 liquidity providers
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

        liquidityProviders.push(
            LiquidityProviderInfo(
                lp1,
                lp1Key,
                "First LP",
                "http://localhost/api1",
                true,
                "both"
            )
        );
        liquidityProviders.push(
            LiquidityProviderInfo(
                lp2,
                lp2Key,
                "Second LP",
                "http://localhost/api2",
                true,
                "pegin"
            )
        );
        liquidityProviders.push(
            LiquidityProviderInfo(
                lp3,
                lp3Key,
                "Third LP",
                "http://localhost/api3",
                true,
                "pegout"
            )
        );
    }

    function test_MatchLPAddressWithAddressRetrievedFromEcrecover()
        public
        view
    {
        LiquidityProviderInfo memory provider = liquidityProviders[0];
        address destinationAddress = accounts[0];

        // Create a test pegin quote
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            0.5 ether,
            destinationAddress,
            destinationAddress
        );

        // Hash the quote
        bytes32 quoteHash = lbc.hashQuote(quote);

        // Sign the quote (EIP-191 personal_sign format)
        bytes32 ethSignedMessageHash = quoteHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            provider.privateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature using SignatureValidator
        bool validSignature = SignatureValidator.verify(
            provider.signer,
            quoteHash,
            signature
        );

        // Recover address from signature
        address signatureAddress = ethSignedMessageHash.recover(signature);

        // Assertions
        assertEq(
            signatureAddress,
            provider.signer,
            "Signature address should match provider address"
        );
        assertTrue(validSignature, "Signature should be valid");
    }

    function test_FailWhenWithdrawAmountGreaterThanTheSenderBalance() public {
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        vm.startPrank(provider.signer);

        // Deposit 100000000 wei
        lbc.deposit{value: 100000000}();

        // Try to withdraw more than balance - should fail with LBC019
        vm.expectRevert("LBC019");
        lbc.withdraw(999999999999999);

        // Withdraw exact balance - should succeed
        lbc.withdraw(100000000);

        vm.stopPrank();
    }

    function test_DepositValueToIncreaseBalanceOfLiquidityProvider() public {
        LiquidityProviderInfo memory provider = liquidityProviders[1];
        uint256 value = 100000000;

        // Get balance before deposit
        uint256 balanceBefore = lbc.getBalance(provider.signer);

        // Perform deposit
        vm.prank(provider.signer);
        vm.expectEmit(true, false, false, true);
        emit LiquidityBridgeContractV2.BalanceIncrease(provider.signer, value);
        lbc.deposit{value: value}();

        // Get balance after deposit
        uint256 balanceAfter = lbc.getBalance(provider.signer);

        // Assert balance increased by expected amount
        assertEq(
            balanceAfter - balanceBefore,
            value,
            "Incorrect LP balance after deposit"
        );
    }

    // Helper function to create a test pegin quote (matching TypeScript getTestPeginQuote)
    function getTestPeginQuote(
        address lbcAddress,
        address liquidityProvider,
        uint256 value,
        address destinationAddress,
        address refundAddress
    ) internal view returns (QuotesV2.PeginQuote memory) {
        uint256 productFeePercentage = 0;
        uint256 productFee = (productFeePercentage * value) / 100;

        // Create nonce from current timestamp
        bytes memory nonceBytes = abi.encodePacked(
            block.timestamp,
            uint256(0x1234567890abcdef)
        );
        int64 nonce = int64(uint64(uint256(keccak256(nonceBytes)) >> 192)); // Take top 64 bits

        return
            QuotesV2.PeginQuote({
                fedBtcAddress: bytes20(DECODED_TEST_FED_ADDRESS),
                lbcAddress: lbcAddress,
                liquidityProviderRskAddress: liquidityProvider,
                btcRefundAddress: DECODED_P2PKH_ZERO_ADDRESS_TESTNET,
                rskRefundAddress: payable(refundAddress),
                liquidityProviderBtcAddress: DECODED_TEST_P2PKH_ADDRESS,
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                contractAddress: destinationAddress,
                data: hex"",
                gasLimit: 21000,
                nonce: nonce,
                value: value,
                agreementTimestamp: uint32(block.timestamp),
                timeForDeposit: 3600,
                callTime: 7200,
                depositConfirmations: 10,
                callOnRegister: false,
                productFeeAmount: productFee,
                gasFee: 100
            });
    }
}
