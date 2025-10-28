// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {LiquidityBridgeContract} from "../../contracts/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractV2} from "../../contracts/legacy/LiquidityBridgeContractV2.sol";
import {QuotesV2} from "../../contracts/legacy/QuotesV2.sol";
import {BridgeMock} from "../../contracts/test-contracts/BridgeMock.sol";
import {Mock} from "../../contracts/test-contracts/Mock.sol";
import {WalletMock} from "../../contracts/test-contracts/WalletMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PegInTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    LiquidityBridgeContractV2 public lbcImpl;
    ERC1967Proxy public lbcProxy;
    LiquidityBridgeContractV2 public lbc;
    BridgeMock public bridgeMock;

    address public lbcOwner;
    address[] public accounts;

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
    address constant ZERO_ADDRESS = address(0);
    bytes constant ANY_HEX = hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    uint256 constant ANY_NUMBER = 10;

    // BTC address constants
    bytes constant DECODED_TEST_FED_ADDRESS = hex"c39bc4b53918d6058134363d6e57e11a22f9e8fb";
    bytes constant DECODED_P2PKH_ZERO_ADDRESS_TESTNET = hex"6f0000000000000000000000000000000000000000";
    bytes constant DECODED_TEST_P2PKH_ADDRESS = hex"6f89abcdefabbaabbaabbaabbaabbaabbaabbaabba";

    function setUp() public {
        lbcOwner = address(this);

        // Create 16 test accounts
        for (uint i = 1; i <= 16; i++) {
            address account = address(uint160(uint256(keccak256(abi.encodePacked("account", i)))));
            vm.deal(account, 100 ether);
            accounts.push(account);
        }

        // Deploy BridgeMock
        bridgeMock = new BridgeMock();

        // Deploy V1 first, then upgrade to V2 (matching the actual deployment)
        LiquidityBridgeContract lbcV1Impl = new LiquidityBridgeContract();
        bytes memory v1InitData = abi.encodeWithSelector(
            LiquidityBridgeContract.initialize.selector,
            payable(address(bridgeMock)),
            0.03 ether, // minCollateral
            0.5 ether, // minPegIn
            uint32(50), // rewardPercentage
            uint32(60), // resignDelayBlocks
            uint256(2300 * 65164000), // dustThreshold
            uint256(1), // btcBlockTime
            false // mainnet
        );
        lbcProxy = new ERC1967Proxy(address(lbcV1Impl), v1InitData);

        // Upgrade to V2
        lbcImpl = new LiquidityBridgeContractV2();
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        vm.store(address(lbcProxy), implementationSlot, bytes32(uint256(uint160(address(lbcImpl)))));

        // Cast to V2 (no need to call initializeV2 since V1 already initialized Ownable/ReentrancyGuard)
        lbc = LiquidityBridgeContractV2(payable(address(lbcProxy)));

        // Create LPs with deterministic private keys
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
        lbc.register{value: LP_COLLATERAL}("First LP", "http://localhost/api1", true, "both");

        vm.prank(lp2, lp2);
        lbc.register{value: LP_COLLATERAL / 2}("Second LP", "http://localhost/api2", true, "pegin");

        vm.prank(lp3, lp3);
        lbc.register{value: LP_COLLATERAL / 2}("Third LP", "http://localhost/api3", true, "pegout");

        liquidityProviders.push(LiquidityProviderInfo(lp1, lp1Key, "First LP", "http://localhost/api1", true, "both"));
        liquidityProviders.push(LiquidityProviderInfo(lp2, lp2Key, "Second LP", "http://localhost/api2", true, "pegin"));
        liquidityProviders.push(LiquidityProviderInfo(lp3, lp3Key, "Third LP", "http://localhost/api3", true, "pegout"));
    }

    // ============ Helper Functions ============

    struct SignResult {
        bytes32 quoteHash;
        bytes signature;
    }

    struct BalanceSnapshot {
        uint256 lpBalance;
        uint256 lpCollateral;
        uint256 lbcEthBalance;
        uint256 userBalance;
        uint256 refundBalance;
    }

    function getTestPeginQuote(
        address lbcAddress,
        address liquidityProvider,
        uint256 value,
        address destinationAddress,
        address refundAddress,
        bytes memory data
    ) internal view returns (QuotesV2.PeginQuote memory quote) {
        int64 nonce = int64(uint64(uint256(keccak256(abi.encodePacked(block.timestamp, uint256(0x1234567890abcdef)))) >> 192));

        quote = QuotesV2.PeginQuote({
            fedBtcAddress: bytes20(DECODED_TEST_FED_ADDRESS),
            lbcAddress: lbcAddress,
            liquidityProviderRskAddress: liquidityProvider,
            btcRefundAddress: DECODED_P2PKH_ZERO_ADDRESS_TESTNET,
            rskRefundAddress: payable(refundAddress),
            liquidityProviderBtcAddress: DECODED_TEST_P2PKH_ADDRESS,
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            contractAddress: destinationAddress,
            data: data,
            gasLimit: 21000,
            nonce: nonce,
            value: value,
            agreementTimestamp: uint32(block.timestamp),
            timeForDeposit: 3600,
            callTime: 7200,
            depositConfirmations: 10,
            callOnRegister: false,
            productFeeAmount: 0,
            gasFee: 100
        });
    }

    function signQuote(bytes32 quoteHash, uint256 privateKey) internal pure returns (bytes memory) {
        bytes32 ethSignedMessageHash = quoteHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    function captureBalances(address lpAddr, address userAddr, address refundAddr) internal view returns (BalanceSnapshot memory) {
        return BalanceSnapshot({
            lpBalance: lbc.getBalance(lpAddr),
            lpCollateral: lbc.getCollateral(lpAddr),
            lbcEthBalance: address(lbc).balance,
            userBalance: userAddr.balance,
            refundBalance: refundAddr.balance
        });
    }

    function totalValue(QuotesV2.PeginQuote memory quote) internal pure returns (uint256) {
        return quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
    }

    function getBtcPaymentBlockHeaders(
        QuotesV2.PeginQuote memory quote,
        uint256 firstConfirmationSeconds,
        uint256 nConfirmationSeconds
    ) internal pure returns (bytes memory firstConfirmationHeader, bytes memory nConfirmationHeader) {
        uint256 firstConfirmationTime = quote.agreementTimestamp + firstConfirmationSeconds;
        uint256 nConfirmationTime = quote.agreementTimestamp + nConfirmationSeconds;

        // Convert timestamps to little-endian 4-byte hex
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

        // BTC header: version(4) + prevHash(32) + merkleRoot(32) + timestamp(4) + bits(4) + nonce(4) = 80 bytes
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

    function getTestMerkleProof() internal pure returns (
        bytes memory blockHeaderHash,
        bytes memory partialMerkleTree,
        bytes32[] memory merkleBranchHashes
    ) {
        blockHeaderHash = hex"02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
        partialMerkleTree = hex"02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
        merkleBranchHashes = new bytes32[](1);
        merkleBranchHashes[0] = 0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326;
    }

    // ============ Tests ============

    function test_CallContractForUser() public {
        Mock mockContract = new Mock();
        mockContract.set(0);

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            20 ether,
            address(mockContract),
            accounts[0],
            abi.encodeWithSelector(Mock.set.selector, int(12))
        );

        BalanceSnapshot memory before = captureBalances(liquidityProviders[0].signer, address(mockContract), accounts[0]);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);

        assertEq(lbc.getBalance(liquidityProviders[0].signer), before.lpBalance);

        vm.prank(liquidityProviders[0].signer);
        int256 result = lbc.registerPegIn(quote, sig, hex"1010", hex"0202", 10);

        assertEq(result, int256(totalValue(quote)));
        assertEq(lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance, totalValue(quote));
        assertEq(address(lbc).balance - before.lbcEthBalance, totalValue(quote));
        assertEq(lbc.getCollateral(liquidityProviders[0].signer), before.lpCollateral);
        assertEq(mockContract.check(), 12);
    }

    function test_FailOnContractCallDueToInvalidLbcAddress() public {
        LiquidityProviderInfo memory provider = liquidityProviders[1];
        address destinationAddress = accounts[0];
        address refundAddress = accounts[1];
        address notLbcAddress = accounts[2];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            notLbcAddress,
            provider.signer,
            0.5 ether,
            destinationAddress,
            refundAddress,
            hex""
        );

        vm.startPrank(provider.signer);

        // Should fail with LBC019 (insufficient balance)
        vm.expectRevert("LBC019");
        lbc.callForUser(quote);

        // Should fail with LBC051 (invalid lbc address)
        vm.expectRevert("LBC051");
        lbc.callForUser{value: quote.value}(quote);

        // registerPegIn should also fail
        vm.expectRevert("LBC051");
        lbc.registerPegIn(quote, ANY_HEX, ANY_HEX, ANY_HEX, ANY_NUMBER);

        vm.stopPrank();
    }

    function test_FailOnContractCallDueToInvalidContractAddress() public {
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        // Use bridge address as contract address (not allowed)
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            0.5 ether,
            address(bridgeMock),
            accounts[0],
            hex""
        );

        vm.startPrank(provider.signer);

        vm.expectRevert("LBC052");
        lbc.hashQuote(quote);

        vm.expectRevert("LBC052");
        lbc.callForUser{value: quote.value}(quote);

        vm.expectRevert("LBC052");
        lbc.registerPegIn(quote, ANY_HEX, ANY_HEX, ANY_HEX, ANY_NUMBER);

        vm.stopPrank();
    }

    function test_FailOnContractCallDueToInvalidUserBtcRefundAddress() public {
        LiquidityProviderInfo memory provider = liquidityProviders[0];
        address destinationAddress = accounts[2];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            0.5 ether,
            destinationAddress,
            destinationAddress,
            hex""
        );

        bytes[] memory invalidAddresses = new bytes[](2);
        invalidAddresses[0] = hex"0000000000000000000000000000000000000012"; // 20 bytes
        invalidAddresses[1] = hex"00000000000000000000000000000000000000000012"; // 22 bytes

        for (uint i = 0; i < invalidAddresses.length; i++) {
            quote.btcRefundAddress = invalidAddresses[i];

            vm.startPrank(provider.signer);

            vm.expectRevert("LBC053");
            lbc.hashQuote(quote);

            vm.expectRevert("LBC053");
            lbc.callForUser{value: quote.value}(quote);

            vm.expectRevert("LBC053");
            lbc.registerPegIn(quote, ANY_HEX, ANY_HEX, ANY_HEX, ANY_NUMBER);

            vm.stopPrank();
        }
    }

    function test_FailOnContractCallDueToInvalidLpBtcAddress() public {
        LiquidityProviderInfo memory provider = liquidityProviders[1];
        address destinationAddress = accounts[0];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            0.5 ether,
            destinationAddress,
            destinationAddress,
            hex""
        );

        bytes[] memory invalidAddresses = new bytes[](2);
        invalidAddresses[0] = hex"0000000000000000000000000000000000000012"; // 20 bytes
        invalidAddresses[1] = hex"00000000000000000000000000000000000000000012"; // 22 bytes

        for (uint i = 0; i < invalidAddresses.length; i++) {
            quote.liquidityProviderBtcAddress = invalidAddresses[i];

            vm.startPrank(provider.signer);

            vm.expectRevert("LBC054");
            lbc.hashQuote(quote);

            vm.expectRevert("LBC054");
            lbc.callForUser{value: quote.value}(quote);

            vm.expectRevert("LBC054");
            lbc.registerPegIn(quote, ANY_HEX, ANY_HEX, ANY_HEX, ANY_NUMBER);

            vm.stopPrank();
        }
    }

    function test_FailOnContractCallDueToQuoteValuePlusFeeBelowMinPegIn() public {
        LiquidityProviderInfo memory provider = liquidityProviders[1];
        address destinationAddress = accounts[2];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            0.1 ether,
            destinationAddress,
            destinationAddress,
            hex""
        );

        vm.startPrank(provider.signer);

        vm.expectRevert("LBC055");
        lbc.hashQuote(quote);

        vm.expectRevert("LBC055");
        lbc.callForUser{value: quote.value}(quote);

        vm.expectRevert("LBC055");
        lbc.registerPegIn(quote, ANY_HEX, ANY_HEX, ANY_HEX, ANY_NUMBER);

        vm.stopPrank();
    }

    function test_ShouldTransferValueForUser() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[1].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.productFeeAmount = 100000000000;

        BalanceSnapshot memory before = captureBalances(liquidityProviders[1].signer, accounts[1], accounts[2]);
        uint256 feeBalanceBefore = ZERO_ADDRESS.balance;

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[1].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[1].signer);
        lbc.callForUser{value: quote.value}(quote);
        assertEq(lbc.getBalance(liquidityProviders[1].signer), before.lpBalance);

        vm.prank(liquidityProviders[1].signer);
        lbc.registerPegIn(quote, sig, ANY_HEX, ANY_HEX, 10);

        assertEq(accounts[1].balance - before.userBalance, quote.value);
        assertEq(address(lbc).balance - before.lbcEthBalance, totalValue(quote) - quote.productFeeAmount);
        assertEq(lbc.getBalance(liquidityProviders[1].signer) - before.lpBalance, totalValue(quote) - quote.productFeeAmount);
        assertEq(ZERO_ADDRESS.balance - feeBalanceBefore, quote.productFeeAmount);
        assertEq(lbc.getCollateral(liquidityProviders[1].signer), before.lpCollateral);
    }

    function test_NotGenerateTransactionToDAOWhenProductFeeIsZeroInRegisterPegIn() public {
        LiquidityProviderInfo memory provider = liquidityProviders[1];
        address destinationAddress = accounts[1];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            10 ether,
            destinationAddress,
            destinationAddress,
            hex""
        );

        uint256 peginAmount = totalValue(quote);

        // Hash and sign
        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes32 ethSignedMessageHash = quoteHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(provider.privateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Setup bridge
        (bytes memory firstHeader, bytes memory nHeader) = getBtcPaymentBlockHeaders(quote, 300, 600);
        uint256 height = 10;
        uint256 feeCollectorBalanceBefore = ZERO_ADDRESS.balance;

        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(height, firstHeader);
        bridgeMock.setHeader(height + quote.depositConfirmations - 1, nHeader);

        // Call for user
        vm.prank(provider.signer);
        lbc.callForUser{value: quote.value}(quote);

        // Register pegin
        vm.recordLogs();
        vm.prank(provider.signer);
        lbc.registerPegIn(quote, signature, ANY_HEX, ANY_HEX, height);

        // Verify no DaoFeeSent event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundDaoFeeSent = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("DaoFeeSent(bytes32,uint256)")) {
                foundDaoFeeSent = true;
                break;
            }
        }
        assertFalse(foundDaoFeeSent, "Should not emit DaoFeeSent");

        // Verify productFeeAmount is 0
        assertEq(quote.productFeeAmount, 0);

        // Verify fee collector balance unchanged
        assertEq(ZERO_ADDRESS.balance, feeCollectorBalanceBefore);
    }

    function test_ThrowErrorInHashQuoteIfSummingQuoteAgreementTimestampAndTimeForDepositCauseOverflow() public {
        address user = accounts[0];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            user,
            user,
            hex""
        );

        quote.agreementTimestamp = 4294967294;
        quote.timeForDeposit = 4294967294;

        vm.expectRevert("LBC071");
        lbc.hashQuote(quote);
    }

    function test_TransferValueAndRefundRemaining() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[1].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );

        uint256 additionalFunds = 1000000000000;
        BalanceSnapshot memory before = captureBalances(liquidityProviders[1].signer, accounts[1], accounts[2]);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[1].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote) + additionalFunds}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[1].signer);
        lbc.callForUser{value: quote.value}(quote);
        assertEq(lbc.getBalance(liquidityProviders[1].signer), before.lpBalance);

        vm.prank(liquidityProviders[1].signer);
        int256 result = lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(result, int256(totalValue(quote) + additionalFunds));
        assertEq(accounts[1].balance - before.userBalance, quote.value);
        assertEq(address(lbc).balance - before.lbcEthBalance, totalValue(quote));
        assertEq(lbc.getBalance(liquidityProviders[1].signer) - before.lpBalance, totalValue(quote));
        assertEq(accounts[2].balance - before.refundBalance, additionalFunds);
        assertEq(lbc.getCollateral(liquidityProviders[1].signer), before.lpCollateral);
    }

    function test_RefundRemainingAmountToLPInCaseRefundingToQuoteRskRefundAddressFails() public {
        WalletMock walletMock = new WalletMock();
        walletMock.setRejectFunds(true);

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            address(walletMock),
            hex""
        );

        uint256 additionalFunds = 1000000000000;
        BalanceSnapshot memory before = captureBalances(liquidityProviders[0].signer, accounts[1], address(walletMock));

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote) + additionalFunds}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);
        assertEq(lbc.getBalance(liquidityProviders[0].signer), before.lpBalance);

        vm.prank(liquidityProviders[0].signer);
        int256 result = lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(result, int256(totalValue(quote) + additionalFunds));
        assertEq(accounts[1].balance - before.userBalance, quote.value);
        assertEq(address(lbc).balance - before.lbcEthBalance, totalValue(quote) + additionalFunds);
        assertEq(lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance, totalValue(quote) + additionalFunds);
        assertEq(address(walletMock).balance, before.refundBalance);
        assertEq(lbc.getCollateral(liquidityProviders[0].signer), before.lpCollateral);
    }

    function test_RefundUserOnFailedCall() public {
        Mock mockContract = new Mock();

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            address(mockContract),
            accounts[2],
            abi.encodeWithSelector(Mock.fail.selector)
        );

        BalanceSnapshot memory before = captureBalances(liquidityProviders[0].signer, address(mockContract), accounts[2]);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);
        assertEq(lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance, quote.value);

        uint256 lpBal = lbc.getBalance(liquidityProviders[0].signer);

        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(lbc.getBalance(liquidityProviders[0].signer) - lpBal, quote.callFee + quote.gasFee);
        assertEq(accounts[2].balance - before.refundBalance, quote.value);
        assertEq(lbc.getCollateral(liquidityProviders[0].signer), before.lpCollateral);
        assertEq(address(mockContract).balance, before.userBalance);
    }

    function test_RefundUserOnMissedCall() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );

        uint256 reward = (quote.penaltyFee * lbc.getRewardPercentage()) / 100;
        BalanceSnapshot memory before = captureBalances(liquidityProviders[0].signer, accounts[1], accounts[2]);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(accounts[1].balance, before.userBalance);
        assertEq(accounts[2].balance - before.refundBalance, quote.value + quote.callFee + quote.gasFee);
        assertEq(lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance, reward);
        assertEq(lbc.getCollateral(liquidityProviders[0].signer), before.lpCollateral - quote.penaltyFee);
        assertEq(address(lbc).balance, before.lbcEthBalance);
    }

    function test_NoOneBeRefundedInRegisterPegInOnMissedCallInCaseRefundingToQuoteRskRefundAddressFails() public {
        WalletMock walletMock = new WalletMock();
        walletMock.setRejectFunds(true);

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            address(walletMock),
            hex""
        );

        uint256 reward = (quote.penaltyFee * lbc.getRewardPercentage()) / 100;
        uint256 walletBalBefore = lbc.getBalance(address(walletMock));
        uint256 lpCollBefore = lbc.getCollateral(liquidityProviders[0].signer);
        uint256 lbcEthBefore = address(lbc).balance;
        uint256 callerBalBefore = lbc.getBalance(accounts[2]);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(11, h2);

        vm.prank(accounts[2]);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(lbc.getCollateral(liquidityProviders[0].signer), lpCollBefore - quote.penaltyFee);
        assertEq(address(walletMock).balance, 0);
        assertEq(address(lbc).balance - lbcEthBefore, totalValue(quote));
        assertEq(lbc.getBalance(accounts[2]) - callerBalBefore, reward);
        assertEq(lbc.getBalance(address(walletMock)), walletBalBefore);
    }

    function test_NotPenalizeWithLateDeposit() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.timeForDeposit = 1;

        uint256 lpCollBefore = lbc.getCollateral(liquidityProviders[0].signer);
        uint256 refundBefore = accounts[2].balance;

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.recordLogs();
        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == keccak256("Penalized(address,uint256,bytes32)"));
        }

        assertEq(lbc.getCollateral(liquidityProviders[0].signer), lpCollBefore);
        assertEq(accounts[2].balance - refundBefore, totalValue(quote));
    }

    function test_NotPenalizeWithInsufficientDeposit() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );

        uint256 insufficientDeposit = totalValue(quote) - 1;
        uint256 lpCollBefore = lbc.getCollateral(liquidityProviders[0].signer);
        uint256 refundBefore = accounts[2].balance;

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: insufficientDeposit}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.recordLogs();
        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == keccak256("Penalized(address,uint256,bytes32)"));
        }

        assertEq(lbc.getCollateral(liquidityProviders[0].signer), lpCollBefore);
        assertEq(accounts[2].balance - refundBefore, insufficientDeposit);
    }

    function test_ShouldPenalizeOnLateCall() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.callTime = 1;

        uint256 reward = (quote.penaltyFee * lbc.getRewardPercentage()) / 100;
        BalanceSnapshot memory before = captureBalances(liquidityProviders[0].signer, accounts[1], accounts[2]);

        vm.warp(block.timestamp + 300);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 100, 200);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);

        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(lbc.getCollateral(liquidityProviders[0].signer), before.lpCollateral - quote.penaltyFee);
        assertEq(accounts[1].balance - before.userBalance, quote.value);
        assertEq(lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance, reward + totalValue(quote));
    }

    function test_NotUnderflowWhenPenaltyIsHigherThanCollateral() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.penaltyFee = LP_COLLATERAL + 1;
        quote.callTime = 1;

        uint256 reward = (LP_COLLATERAL / 2 * lbc.getRewardPercentage()) / 100;
        BalanceSnapshot memory before = captureBalances(liquidityProviders[0].signer, accounts[1], accounts[2]);

        vm.warp(block.timestamp + 300);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 100, 200);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);

        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance, reward + totalValue(quote));
        assertEq(accounts[1].balance, before.userBalance + quote.value);
        assertEq(lbc.getCollateral(liquidityProviders[0].signer), 0);
    }

    function test_ShouldNotAllowAttackerToStealFunds() public {
        // Attacker controls a liquidity provider and destination address
        LiquidityProviderInfo memory attackingLP = liquidityProviders[0];
        address attackerDestAddress = accounts[9];

        // Good LP adds funds
        vm.prank(liquidityProviders[1].signer);
        lbc.deposit{value: 20 ether}();

        // Create evil quote where attacker is both LP and dest
        QuotesV2.PeginQuote memory quote = QuotesV2.PeginQuote({
            fedBtcAddress: bytes20(0),
            btcRefundAddress: hex"000000000000000000000000000000000000000000",
            liquidityProviderBtcAddress: hex"000000000000000000000000000000000000000000",
            rskRefundAddress: payable(attackerDestAddress),
            liquidityProviderRskAddress: attackingLP.signer, // Use attacking LP address
            data: hex"",
            gasLimit: 30000,
            callFee: 1,
            nonce: 1,
            lbcAddress: address(lbc),
            agreementTimestamp: 1661788988,
            timeForDeposit: 600,
            callTime: 600,
            depositConfirmations: 10,
            penaltyFee: 0,
            callOnRegister: true,
            productFeeAmount: 1,
            gasFee: 1,
            value: 10 ether,
            contractAddress: attackerDestAddress
        });

        uint256 transferredInBTC = 100; // Only 100 wei transferred

        // Hash and sign
        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes32 ethSignedMessageHash = quoteHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackingLP.privateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Setup bridge
        (bytes memory firstHeader, bytes memory nHeader) = getBtcPaymentBlockHeaders(quote, 300, 600);
        uint256 height = 10;

        bridgeMock.setHeader(height, firstHeader);
        bridgeMock.setHeader(height + quote.depositConfirmations - 1, nHeader);
        bridgeMock.setPegin{value: transferredInBTC}(quoteHash);

        // Try to exploit
        vm.prank(attackingLP.signer);
        vm.expectRevert("LBC057");
        lbc.registerPegIn(quote, signature, hex"0101", hex"0202", height);
    }

    function test_PayWithInsufficientDepositThatIsNotLowerThanAgreedAmountMinusDelta() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            0.7 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.callFee = 0.00001 ether;
        quote.gasFee = 0.00003 ether;

        uint256 delta = totalValue(quote) / 10000;
        uint256 peginAmount = totalValue(quote) - delta;

        BalanceSnapshot memory before = captureBalances(liquidityProviders[0].signer, accounts[1], accounts[2]);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 100, 200);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(21, h2);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);

        vm.prank(liquidityProviders[0].signer);
        int256 result = lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(result, int256(peginAmount));
        assertEq(lbc.getCollateral(liquidityProviders[0].signer), before.lpCollateral);
        assertEq(lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance, peginAmount);
        assertEq(address(lbc).balance - before.lbcEthBalance, peginAmount);
        assertEq(accounts[1].balance - before.userBalance, quote.value);
    }

    function test_RevertOnInsufficientDeposit() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            0.7 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.callFee = 0.000005 ether;
        quote.gasFee = 0.000006 ether;

        uint256 peginAmount = totalValue(quote) - (totalValue(quote) / 10000) - 1;

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 100, 200);
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(21, h2);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);

        vm.prank(liquidityProviders[0].signer);
        vm.expectRevert("LBC057");
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);
    }

    function test_ShouldDemonstrateFundsBeingLockedWhenRskRefundAddressRevertsOnRegisterPegInWithoutCallForUser() public {
        WalletMock maliciousContract = new WalletMock();
        maliciousContract.setRejectFunds(true);

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            address(maliciousContract),
            hex""
        );

        uint256 lbcBefore = address(lbc).balance;
        uint256 malBalBefore = lbc.getBalance(address(maliciousContract));

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.recordLogs();
        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, hex"0101", hex"0202", 10);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundBalInc = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BalanceIncrease(address,uint256)")) {
                (address dest, uint256 amt) = abi.decode(logs[i].data, (address, uint256));
                if ((dest == address(maliciousContract) || dest == liquidityProviders[0].signer) && amt == totalValue(quote)) {
                    foundBalInc = true;
                }
            }
        }
        assertFalse(foundBalInc);

        assertEq(lbc.getBalance(address(maliciousContract)), malBalBefore);
        assertEq(address(lbc).balance - lbcBefore, totalValue(quote));
        assertEq(address(maliciousContract).balance, 0);
    }

    function test_ShouldHandleRefundCorrectlyWhenRskRefundAddressCanReceiveFundsOnRegisterPegInWithoutCallForUser() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );

        uint256 refundBefore = accounts[2].balance;

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(quoteHash, liquidityProviders[0].privateKey);

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(quote, 300, 600);
        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.recordLogs();
        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, hex"0101", hex"0202", 10);

        assertEq(accounts[2].balance - refundBefore, totalValue(quote));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BalanceIncrease(address,uint256)")) {
                (address dest, uint256 amt) = abi.decode(logs[i].data, (address, uint256));
                assertFalse(dest == accounts[2] && amt == totalValue(quote));
            }
        }

        assertEq(lbc.getBalance(accounts[2]), 0);
    }
}
