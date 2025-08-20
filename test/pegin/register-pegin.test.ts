import {
  loadFixture,
  mine,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {
  callForUserExecutedFixture,
  deployPegInContractFixture,
} from "./fixtures";
import {
  COLLATERAL_CONSTANTS,
  PEGIN_CONSTANTS,
  PegInStates,
  ProviderType,
} from "../utils/constants";
import {
  getBtcPaymentBlockHeaders,
  getRewardForQuote,
  getTestPeginQuote,
  totalValue,
} from "../utils/quotes";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Quotes__factory } from "../../typechain-types/factories/contracts/libraries";

describe("PegInContract registerPegIn function should", () => {
  it("refund LP when call was done and the user paid the correct amount", async () => {
    const {
      contract,
      liquidityProvider,
      quote,
      signature,
      quoteHash,
      bridgeMock,
      collateralManagement,
      user,
    } = await loadFixture(callForUserExecutedFixture);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    await expect(
      contract
        .connect(liquidityProvider)
        .deposit({ value: ethers.parseEther("3") })
    ).not.to.be.reverted;
    const tx = contract
      .connect(liquidityProvider)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(tx).not.to.emit(collateralManagement, "Penalized");
    await expect(tx).not.to.emit(contract, "Refund");
    await expect(tx).not.to.emit(contract, "CallForUser");
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx)
      .to.emit(contract, "DaoContribution")
      .withArgs(liquidityProvider.address, quote.productFeeAmount);
    await expect(contract.getCurrentContribution()).to.eventually.eq(
      quote.productFeeAmount
    );
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, liquidityProvider, contract],
      [0n, 0n, peginAmount]
    );
    await expect(contract.getBalance(liquidityProvider)).to.eventually.eq(
      peginAmount + ethers.parseEther("3") - BigInt(quote.productFeeAmount)
    );
  });

  it("refund LP when call was done and the user overpaid the quote", async () => {
    const {
      contract,
      liquidityProvider,
      quote,
      signature,
      quoteHash,
      bridgeMock,
      collateralManagement,
      user,
    } = await loadFixture(callForUserExecutedFixture);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    const extraPaid = ethers.parseEther("5.5");
    await bridgeMock.setPegin(quoteHash, { value: peginAmount + extraPaid });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    const tx = contract
      .connect(liquidityProvider)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );

    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount + extraPaid);
    await expect(tx).not.to.emit(collateralManagement, "Penalized");
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(user.address, quoteHash, extraPaid, true);
    await expect(tx).not.to.emit(contract, "CallForUser");
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx)
      .to.emit(contract, "DaoContribution")
      .withArgs(liquidityProvider.address, quote.productFeeAmount);
    await expect(contract.getCurrentContribution()).to.eventually.eq(
      quote.productFeeAmount
    );
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, liquidityProvider, contract],
      [extraPaid, 0n, peginAmount]
    );
    await expect(contract.getBalance(liquidityProvider)).to.eventually.eq(
      peginAmount - BigInt(quote.productFeeAmount)
    );
  });

  it("refund LP if change payment to the user fails", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];

    const WalletMock = await ethers.getContractFactory("WalletMock");
    const refundWallet = await WalletMock.deploy();
    const refundAddress = await refundWallet.getAddress();

    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: user.address,
      refundAddress: refundAddress,
      productFeePercentage: 2,
    });
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    const extraPaid = ethers.parseEther("5.5");
    await bridgeMock.setPegin(quoteHash, { value: peginAmount + extraPaid });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    await expect(refundWallet.setRejectFunds(true)).not.to.be.reverted;
    await expect(
      contract.connect(fullLp).callForUser(quote, { value: quote.value })
    ).not.to.be.reverted;
    const tx = contract
      .connect(fullLp)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount + extraPaid);
    await expect(tx).not.to.emit(collateralManagement, "Penalized");
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(refundAddress, quoteHash, extraPaid, false);
    await expect(tx).not.to.emit(contract, "CallForUser");
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx)
      .to.emit(contract, "DaoContribution")
      .withArgs(fullLp.address, quote.productFeeAmount);
    await expect(contract.getCurrentContribution()).to.eventually.eq(
      quote.productFeeAmount
    );
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract],
      [0n, 0n, peginAmount + extraPaid]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(
      peginAmount + extraPaid - BigInt(quote.productFeeAmount)
    );
  });

  it("refund user when call was not done and user under paid the quote", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];

    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote) - ethers.parseEther("0.0001");
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    const tx = contract
      .connect(fullLp)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(tx).not.to.emit(collateralManagement, "Penalized");
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(user.address, quoteHash, peginAmount, true);
    await expect(tx).not.to.emit(contract, "CallForUser");
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx).not.to.emit(contract, "DaoContribution");
    await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract],
      [peginAmount, 0n, 0n]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
  });

  it("refund user when call was not done and user didn't pay the quote on time", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];

    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: Number(quote.timeForDeposit) + 1,
        nConfirmationSeconds: 600,
      });

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    const tx = contract
      .connect(fullLp)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(tx).not.to.emit(collateralManagement, "Penalized");
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(user.address, quoteHash, peginAmount, true);
    await expect(tx).not.to.emit(contract, "CallForUser");
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx).not.to.emit(contract, "DaoContribution");
    await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract],
      [peginAmount, 0n, 0n]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
  });

  it("refund user when call was not done and they paid properly", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const registerCaller = signers[2];

    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    const tx = contract
      .connect(registerCaller)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(tx)
      .to.emit(collateralManagement, "Penalized")
      .withArgs(
        fullLp.address,
        quoteHash,
        ProviderType.PegIn,
        quote.penaltyFee,
        getRewardForQuote(quote, COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE)
      );
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(user.address, quoteHash, peginAmount, true);
    await expect(tx).not.to.emit(contract, "CallForUser");
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx).not.to.emit(contract, "DaoContribution");
    await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract],
      [peginAmount, 0n, 0n]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
  });

  it("revert if quote was already registered", async () => {
    const {
      contract,
      liquidityProvider,
      quote,
      signature,
      quoteHash,
      bridgeMock,
    } = await loadFixture(callForUserExecutedFixture);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    await expect(
      contract
        .connect(liquidityProvider)
        .registerPegIn(
          quote,
          signature,
          PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
          PEGIN_CONSTANTS.PMT_MOCK,
          height
        )
    ).not.to.be.reverted;
    await expect(
      contract
        .connect(liquidityProvider)
        .registerPegIn(
          quote,
          signature,
          PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
          PEGIN_CONSTANTS.PMT_MOCK,
          height
        )
    )
      .to.be.revertedWithCustomError(contract, "QuoteAlreadyProcessed")
      .withArgs(quoteHash);
  });

  it("revert if signature is not correct", async () => {
    const { contract, liquidityProvider, quote, quoteHash, bridgeMock } =
      await loadFixture(callForUserExecutedFixture);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    const fakeSignature = await liquidityProvider.signMessage(
      "0x9e1ff8110dede851f2d517bf6567987d9f4555f70e27054cb1d2769cc4e9005d"
    );

    await expect(
      contract
        .connect(liquidityProvider)
        .registerPegIn(
          quote,
          fakeSignature,
          PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
          PEGIN_CONSTANTS.PMT_MOCK,
          height
        )
    )
      .to.be.revertedWithCustomError(contract, "IncorrectSignature")
      .withArgs(liquidityProvider, quoteHash, fakeSignature);
  });

  it("revert if height is bigger than supported", async () => {
    const { contract, liquidityProvider, quote, signature } = await loadFixture(
      callForUserExecutedFixture
    );
    const MAX_INT_32 = 2_147_483_647n;
    const height = MAX_INT_32 + 1n;

    await expect(
      contract
        .connect(liquidityProvider)
        .registerPegIn(
          quote,
          signature,
          PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
          PEGIN_CONSTANTS.PMT_MOCK,
          height
        )
    )
      .to.be.revertedWithCustomError(contract, "Overflow")
      .withArgs(MAX_INT_32);
  });

  it("revert if there aren't enough confirmations in the bridge yet", async () => {
    const {
      contract,
      liquidityProvider,
      quote,
      quoteHash,
      signature,
      bridgeMock,
    } = await loadFixture(callForUserExecutedFixture);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    await bridgeMock.setPeginError(
      PEGIN_CONSTANTS.BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR
    );

    await expect(
      contract
        .connect(liquidityProvider)
        .registerPegIn(
          quote,
          signature,
          PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
          PEGIN_CONSTANTS.PMT_MOCK,
          height
        )
    ).to.be.revertedWithCustomError(contract, "NotEnoughConfirmations");
  });

  it("revert on unexpected bridge error", async () => {
    const {
      contract,
      liquidityProvider,
      quote,
      quoteHash,
      signature,
      bridgeMock,
    } = await loadFixture(callForUserExecutedFixture);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const ERROR_CODE = -505;
    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    await bridgeMock.setPeginError(ERROR_CODE);

    await expect(
      contract
        .connect(liquidityProvider)
        .registerPegIn(
          quote,
          signature,
          PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
          PEGIN_CONSTANTS.PMT_MOCK,
          height
        )
    )
      .to.be.revertedWithCustomError(contract, "UnexpectedBridgeError")
      .withArgs(ERROR_CODE);
  });

  [
    PEGIN_CONSTANTS.BRIDGE_REFUNDED_USER_ERROR_CODE,
    PEGIN_CONSTANTS.BRIDGE_REFUNDED_LP_ERROR_CODE,
  ].forEach((errorCode) => {
    it(`revert if locking cap was passed with code ${errorCode.toString()}`, async () => {
      const {
        contract,
        liquidityProvider,
        quote,
        quoteHash,
        signature,
        bridgeMock,
        collateralManagement,
        user,
      } = await loadFixture(callForUserExecutedFixture);
      const { firstConfirmationHeader, nConfirmationHeader } =
        getBtcPaymentBlockHeaders({
          quote: quote,
          firstConfirmationSeconds: 300,
          nConfirmationSeconds: 600,
        });
      const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
      const peginAmount = totalValue(quote);
      await bridgeMock.setPegin(quoteHash, { value: peginAmount });
      await bridgeMock.setHeader(height, firstConfirmationHeader);
      await bridgeMock.setHeader(
        height + Number(quote.depositConfirmations) - 1,
        nConfirmationHeader
      );

      await expect(bridgeMock.setPeginError(errorCode)).not.to.be.reverted;
      const tx = contract
        .connect(liquidityProvider)
        .registerPegIn(
          quote,
          signature,
          PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
          PEGIN_CONSTANTS.PMT_MOCK,
          height
        );
      await expect(tx).not.to.emit(contract, "PegInRegistered");
      await expect(tx).not.to.emit(collateralManagement, "Penalized");
      await expect(tx).not.to.emit(contract, "Refund");
      await expect(tx).not.to.emit(contract, "CallForUser");
      await expect(tx)
        .to.emit(contract, "BridgeCapExceeded")
        .withArgs(quoteHash, errorCode);
      await expect(tx).not.to.emit(contract, "DaoContribution");
      await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
      await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
        PegInStates.PROCESSED_QUOTE
      );
      await expect(tx).to.changeEtherBalances(
        [user, liquidityProvider, contract],
        [0n, 0n, 0n]
      );
      await expect(contract.getBalance(liquidityProvider)).to.eventually.eq(0n);
    });
  });

  it("penalize LP if the call for user wasn't made on time", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const registerCaller = signers[2];

    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: user.address,
      refundAddress: user.address,
      productFeePercentage: 3,
    });
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: Number(quote.callTime) + 1,
      });
    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    await mine(3, {
      interval: Number(quote.agreementTimestamp) + Number(quote.callTime),
    });
    await expect(
      contract.connect(fullLp).callForUser(quote, { value: quote.value })
    ).not.to.be.reverted;
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
    const tx = contract
      .connect(registerCaller)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(tx)
      .to.emit(collateralManagement, "Penalized")
      .withArgs(
        fullLp.address,
        quoteHash,
        ProviderType.PegIn,
        quote.penaltyFee,
        getRewardForQuote(quote, COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE)
      );
    await expect(tx).not.to.emit(contract, "Refund");
    await expect(tx).not.to.emit(contract, "CallForUser");
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx)
      .to.emit(contract, "DaoContribution")
      .withArgs(fullLp.address, quote.productFeeAmount);
    await expect(contract.getCurrentContribution()).to.eventually.eq(
      quote.productFeeAmount
    );
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract],
      [0n, 0n, peginAmount]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(
      peginAmount - BigInt(quote.productFeeAmount)
    );
  });

  it("revert if the paid amount was way lower than the quote amount", async () => {
    const { contract, fullLp, signers, bridgeMock } = await loadFixture(
      deployPegInContractFixture
    );
    const lbcAddress = await contract.getAddress();
    const user = signers[0];

    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    const QuotesLib = new ethers.Contract(
      ethers.ZeroAddress,
      Quotes__factory.abi,
      ethers.provider
    );

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote) - ethers.parseEther("0.1");
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    const minValue = totalValue(quote) - totalValue(quote) / 10_000n;
    await expect(
      contract
        .connect(fullLp)
        .registerPegIn(
          quote,
          signature,
          PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
          PEGIN_CONSTANTS.PMT_MOCK,
          height
        )
    )
      .to.be.revertedWithCustomError(QuotesLib, "AmountTooLow")
      .withArgs(peginAmount, minValue);
    await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.UNPROCESSED_QUOTE
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
  });

  it("execute call for user if callOnRegister is true", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const registerCaller = signers[1];

    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    quote.callOnRegister = true;
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    const tx = contract
      .connect(registerCaller)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    const refundAmount =
      BigInt(quote.gasFee) +
      BigInt(quote.callFee) +
      BigInt(quote.productFeeAmount);
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(tx)
      .to.emit(collateralManagement, "Penalized")
      .withArgs(
        fullLp.address,
        quoteHash,
        ProviderType.PegIn,
        quote.penaltyFee,
        getRewardForQuote(quote, COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE)
      );
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(quote.rskRefundAddress, quoteHash, refundAmount, true);
    await expect(tx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        registerCaller,
        quote.contractAddress,
        quoteHash,
        quote.gasLimit,
        quote.value,
        quote.data,
        true
      );
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx).not.to.emit(contract, "DaoContribution");
    await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract],
      [peginAmount, 0n, 0n]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
  });

  it("refund full amount if call on register fails", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const registerCaller = signers[1];
    const WalletMock = await ethers.getContractFactory("WalletMock");
    const wallet = await WalletMock.deploy();
    const contractAddress = await wallet.getAddress();

    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: contractAddress,
      refundAddress: user.address,
    });
    quote.callOnRegister = true;
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    await wallet.setRejectFunds(true);
    const tx = contract
      .connect(registerCaller)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(tx)
      .to.emit(collateralManagement, "Penalized")
      .withArgs(
        fullLp.address,
        quoteHash,
        ProviderType.PegIn,
        quote.penaltyFee,
        getRewardForQuote(quote, COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE)
      );
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(quote.rskRefundAddress, quoteHash, peginAmount, true);
    await expect(tx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        registerCaller,
        quote.contractAddress,
        quoteHash,
        quote.gasLimit,
        quote.value,
        quote.data,
        false
      );
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx).not.to.emit(contract, "DaoContribution");
    await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract],
      [peginAmount, 0n, 0n]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
  });

  it("not allow reentrancy when refunding the user", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const registerCaller = signers[2];
    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;

    const reentrantQuote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    reentrantQuote.gasLimit = BigInt(reentrantQuote.gasLimit) * 3n;
    const reentrantHash = await contract
      .hashPegInQuote(reentrantQuote)
      .then((result) => ethers.getBytes(result));
    const reentrantSignature = await fullLp.signMessage(reentrantHash);

    const ReentrancyCaller = await ethers.getContractFactory(
      "ReentrancyCaller"
    );
    const reentrancyCallerContract = await ReentrancyCaller.deploy();
    const reentrantData = contract.interface.encodeFunctionData(
      "registerPegIn",
      [
        reentrantQuote,
        reentrantSignature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height,
      ]
    );
    const reentrantAddress = await reentrancyCallerContract.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: user.address,
      refundAddress: reentrantAddress,
      data: reentrantData,
    });
    quote.gasLimit = BigInt(quote.gasLimit) * 3n;
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    await expect(reentrancyCallerContract.setData(reentrantData)).not.to.be
      .reverted;
    const tx = contract
      .connect(registerCaller)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(tx)
      .to.emit(collateralManagement, "Penalized")
      .withArgs(
        fullLp,
        quoteHash,
        ProviderType.PegIn,
        quote.penaltyFee,
        getRewardForQuote(quote, COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE)
      );
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(reentrantAddress, quoteHash, peginAmount, false);
    await expect(tx).not.to.emit(contract, "CallForUser");
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx).not.to.emit(contract, "DaoContribution");
    await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract],
      [0n, 0n, peginAmount]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
  });
  it("not allow reentrancy when paying change to the user", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const registerCaller = signers[2];
    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;

    const reentrantQuote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    reentrantQuote.gasLimit = BigInt(reentrantQuote.gasLimit) * 3n;
    const reentrantHash = await contract
      .hashPegInQuote(reentrantQuote)
      .then((result) => ethers.getBytes(result));
    const reentrantSignature = await fullLp.signMessage(reentrantHash);

    const ReentrancyCaller = await ethers.getContractFactory(
      "ReentrancyCaller"
    );
    const reentrancyCallerContract = await ReentrancyCaller.deploy();
    const reentrantData = contract.interface.encodeFunctionData(
      "registerPegIn",
      [
        reentrantQuote,
        reentrantSignature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height,
      ]
    );
    const reentrantAddress = await reentrancyCallerContract.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: user.address,
      refundAddress: reentrantAddress,
      data: reentrantData,
    });
    quote.gasLimit = BigInt(quote.gasLimit) * 3n;
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const peginAmount = totalValue(quote);
    const extraPaid = ethers.parseEther("1");
    await bridgeMock.setPegin(quoteHash, { value: peginAmount + extraPaid });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    await expect(reentrancyCallerContract.setData(reentrantData)).not.to.be
      .reverted;
    await expect(
      contract.connect(fullLp).callForUser(quote, { value: quote.value })
    ).not.to.be.reverted;
    const tx = contract
      .connect(registerCaller)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount + extraPaid);
    await expect(tx).not.to.emit(collateralManagement, "Penalized");
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(reentrantAddress, quoteHash, extraPaid, false);
    await expect(tx).not.to.emit(contract, "CallForUser");
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx).not.to.emit(contract, "DaoContribution");
    await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract],
      [0n, 0n, peginAmount + extraPaid]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(
      peginAmount + extraPaid
    );
  });

  it("not allow reentrancy when executing callForUser on register", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const registerCaller = signers[2];
    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;

    const reentrantQuote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    reentrantQuote.gasLimit = BigInt(reentrantQuote.gasLimit) * 3n;
    const reentrantHash = await contract
      .hashPegInQuote(reentrantQuote)
      .then((result) => ethers.getBytes(result));
    const reentrantSignature = await fullLp.signMessage(reentrantHash);

    const ReentrancyCaller = await ethers.getContractFactory(
      "ReentrancyCaller"
    );
    const reentrancyCallerContract = await ReentrancyCaller.deploy();
    const reentrantData = contract.interface.encodeFunctionData(
      "registerPegIn",
      [
        reentrantQuote,
        reentrantSignature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height,
      ]
    );
    const reentrantAddress = await reentrancyCallerContract.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: reentrantAddress,
      refundAddress: user.address,
      data: reentrancyCallerContract.interface.encodeFunctionData(
        "reentrantCall"
      ),
    });
    quote.gasLimit = BigInt(quote.gasLimit) * 10n;
    quote.callOnRegister = true;
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const peginAmount = totalValue(quote);
    const refundAmount =
      BigInt(quote.callFee) +
      BigInt(quote.gasFee) +
      BigInt(quote.productFeeAmount);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    const reentrancySelector = contract.interface.getError(
      "ReentrancyGuardReentrantCall"
    )?.selector;

    await expect(reentrancyCallerContract.setData(reentrantData)).not.to.be
      .reverted;
    const tx = contract
      .connect(registerCaller)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(tx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        registerCaller,
        quote.contractAddress,
        quoteHash,
        quote.gasLimit,
        quote.value,
        quote.data,
        true
      );
    await expect(tx)
      .to.emit(collateralManagement, "Penalized")
      .withArgs(
        fullLp,
        quoteHash,
        ProviderType.PegIn,
        quote.penaltyFee,
        getRewardForQuote(quote, COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE)
      );
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(user.address, quoteHash, refundAmount, true);
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx).not.to.emit(contract, "DaoContribution");
    await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx)
      .to.emit(reentrancyCallerContract, "ReentrancyReverted")
      .withArgs(reentrancySelector);
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract, reentrancyCallerContract],
      [refundAmount, 0n, 0n, quote.value]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
    await expect(reentrancyCallerContract.getRevertReason()).to.eventually.eq(
      reentrancySelector
    );
  });

  it("refund user if call was done but failed", async () => {
    const { contract, fullLp, signers, bridgeMock, collateralManagement } =
      await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const height = PEGIN_CONSTANTS.HEIGHT_MOCK;

    const WalletMock = await ethers.getContractFactory("WalletMock");
    const wallet = await WalletMock.deploy();
    const walletAddress = await wallet.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1.2"),
      destinationAddress: walletAddress,
      refundAddress: user.address,
      productFeePercentage: 2,
    });
    const quoteHash = await contract
      .hashPegInQuote(quote)
      .then((result) => ethers.getBytes(result));
    const signature = await fullLp.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const peginAmount = totalValue(quote);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    await wallet.setRejectFunds(true);
    const lpRefundAmount = BigInt(quote.callFee) + BigInt(quote.gasFee);

    const callForUserTx = await contract
      .connect(fullLp)
      .callForUser(quote, { value: quote.value });
    await expect(callForUserTx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        fullLp,
        quote.contractAddress,
        quoteHash,
        quote.gasLimit,
        quote.value,
        quote.data,
        false
      );
    const tx = contract
      .connect(fullLp)
      .registerPegIn(
        quote,
        signature,
        PEGIN_CONSTANTS.RAW_TRANSACTION_MOCK,
        PEGIN_CONSTANTS.PMT_MOCK,
        height
      );
    await expect(tx)
      .to.emit(contract, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(tx).not.to.emit(collateralManagement, "Penalized");
    await expect(tx)
      .to.emit(contract, "Refund")
      .withArgs(user.address, quoteHash, quote.value, true);
    await expect(tx).not.to.emit(contract, "BridgeCapExceeded");
    await expect(tx)
      .to.emit(contract, "DaoContribution")
      .withArgs(fullLp.address, quote.productFeeAmount);
    await expect(contract.getCurrentContribution()).to.eventually.eq(
      quote.productFeeAmount
    );
    await expect(contract.getQuoteStatus(quoteHash)).to.eventually.eq(
      PegInStates.PROCESSED_QUOTE
    );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, contract],
      [quote.value, 0n, lpRefundAmount + BigInt(quote.productFeeAmount)]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(
      lpRefundAmount + BigInt(quote.value)
    );
  });
});
