import {
  loadFixture,
  mine,
  mineUpTo,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployPegOutContractFixture, paidPegOutFixture } from "./fixtures";
import { expect } from "chai";
import {
  getBtcPaymentBlockHeaders,
  getRewardForQuote,
  getTestPegoutQuote,
  totalValue,
} from "../utils/quotes";
import {
  BtcAddressType,
  generateRawTx,
  getTestBtcAddress,
  getTestMerkleProof,
  satToWei,
  WEI_TO_SAT_CONVERSION,
  weiToSat,
} from "../utils/btc";
import { getBytes } from "ethers";
import { ethers } from "hardhat";
import {
  COLLATERAL_CONSTANTS,
  PEGOUT_CONSTANTS,
  ProviderType,
} from "../utils/constants";

const AMOUNTS_TO_TEST_REFUND = [
  "500",
  "100",
  "50",
  "15",
  "1",
  "1.1",
  "1.0001",
  "1.00000001",
  "1.000000001",
  "1.000000000000000001",
];

const BTC_ADDRESS_TYPES = ["p2pkh", "p2sh", "p2wpkh", "p2wsh", "p2tr"];

describe("PegOutContract refundPegOut function should", () => {
  it("revert if LP resigned", async () => {
    const { collateralManagement, usedLp, contract, quoteHash, quote } =
      await loadFixture(paidPegOutFixture);

    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();
    const btcTx = await generateRawTx(contract, quote);

    await expect(collateralManagement.connect(usedLp).resign()).not.to.be
      .reverted;
    await expect(
      contract
        .connect(usedLp)
        .refundPegOut(
          getBytes(quoteHash),
          btcTx,
          blockHeaderHash,
          partialMerkleTree,
          merkleBranchHashes
        )
    )
      .to.be.revertedWithCustomError(contract, "ProviderNotRegistered")
      .withArgs(usedLp.address);
  });

  it("revert if the quote was not paid", async () => {
    const { pegOutLp, contract, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: pegOutLp,
      refundAddress: user.address,
      value: ethers.parseEther("1"),
    });

    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();
    const btcTx = await generateRawTx(contract, quote);
    const quoteHash = await contract.hashPegOutQuote(quote);

    await expect(
      contract
        .connect(pegOutLp)
        .refundPegOut(
          getBytes(quoteHash),
          btcTx,
          blockHeaderHash,
          partialMerkleTree,
          merkleBranchHashes
        )
    )
      .to.be.revertedWithCustomError(contract, "QuoteNotFound")
      .withArgs(getBytes(quoteHash));
  });

  it("revert if it's no called by the LP", async () => {
    const { fullLp, contract, quoteHash, quote, usedLp } = await loadFixture(
      paidPegOutFixture
    );

    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();
    const btcTx = await generateRawTx(contract, quote);

    await expect(
      contract
        .connect(fullLp)
        .refundPegOut(
          getBytes(quoteHash),
          btcTx,
          blockHeaderHash,
          partialMerkleTree,
          merkleBranchHashes
        )
    )
      .to.be.revertedWithCustomError(contract, "InvalidSender")
      .withArgs(usedLp.address, fullLp.address);
  });

  it("revert if the btc tx is not related to the quote", async () => {
    const { contract, quoteHash, quote, usedLp } = await loadFixture(
      paidPegOutFixture
    );

    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();

    const otherQuote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: usedLp,
      refundAddress: String(quote.rskRefundAddress), // eslint-disable-line @typescript-eslint/no-base-to-string
      value: ethers.parseEther("1"),
    });
    const otherQuoteHash = await contract.hashPegOutQuote(otherQuote);
    const btcTx = await generateRawTx(contract, otherQuote);

    await expect(
      contract
        .connect(usedLp)
        .refundPegOut(
          getBytes(quoteHash),
          btcTx,
          blockHeaderHash,
          partialMerkleTree,
          merkleBranchHashes
        )
    )
      .to.be.revertedWithCustomError(contract, "InvalidQuoteHash")
      .withArgs(getBytes(quoteHash), getBytes(otherQuoteHash));
  });

  it("revert if the null data is malformed", async () => {
    const { contract, quoteHash, usedLp } = await loadFixture(
      paidPegOutFixture
    );

    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();

    const invalidBtcTx =
      "0x0100000001013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40000000006a47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4ffffffff0200e1f505000000001976a914be07cb9dfdc7dfa88436fa4128410e2126d6979688ac0000000000000000216a194eb34f85cf4b36975d028a89e6dd057a755bcdd2208a854f2fb202f4ab18f700000000";

    await expect(
      contract.connect(usedLp).refundPegOut(
        getBytes(quoteHash),
        invalidBtcTx, // the quote hash in this tx has 31 bytes instead of 32
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      )
    )
      .to.be.revertedWithCustomError(contract, "MalformedTransaction")
      .withArgs(
        getBytes(
          "0x194eb34f85cf4b36975d028a89e6dd057a755bcdd2208a854f2fb202f4ab18f7"
        )
      );
  });

  it("revert if contract can't get confirmations from the bridge", async () => {
    const { contract, quoteHash, quote, usedLp, bridgeMock } =
      await loadFixture(paidPegOutFixture);

    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();
    const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
      quote: quote,
      firstConfirmationSeconds: 100,
      nConfirmationSeconds: 600,
    });
    await bridgeMock.setHeaderByHash(blockHeaderHash, firstConfirmationHeader);
    await bridgeMock.setConfirmations(-5);
    const btcTx = await generateRawTx(contract, quote);

    await expect(
      contract
        .connect(usedLp)
        .refundPegOut(
          getBytes(quoteHash),
          btcTx,
          blockHeaderHash,
          partialMerkleTree,
          merkleBranchHashes
        )
    )
      .to.be.revertedWithCustomError(contract, "UnableToGetConfirmations")
      .withArgs(-5);
  });

  it("revert if the btc tx doesn't have enough confirmations", async () => {
    const { contract, quoteHash, quote, usedLp, bridgeMock } =
      await loadFixture(paidPegOutFixture);

    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();
    const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
      quote: quote,
      firstConfirmationSeconds: 100,
      nConfirmationSeconds: 600,
    });
    await bridgeMock.setHeaderByHash(blockHeaderHash, firstConfirmationHeader);
    await bridgeMock.setConfirmations(1);
    const btcTx = await generateRawTx(contract, quote);

    await expect(
      contract
        .connect(usedLp)
        .refundPegOut(
          getBytes(quoteHash),
          btcTx,
          blockHeaderHash,
          partialMerkleTree,
          merkleBranchHashes
        )
    )
      .to.be.revertedWithCustomError(contract, "NotEnoughConfirmations")
      .withArgs(quote.transferConfirmations, 1);
  });

  ["0.9", "0.9999", "0.99999999"].forEach(
    // test quote value is 1
    (amount) => {
      it("revert if the btc tx doesn't have a high enough amount", async () => {
        const { contract, quoteHash, quote, usedLp, bridgeMock } =
          await loadFixture(paidPegOutFixture);

        const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
          getTestMerkleProof();
        const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
          quote: quote,
          firstConfirmationSeconds: 100,
          nConfirmationSeconds: 600,
        });
        await bridgeMock.setHeaderByHash(
          blockHeaderHash,
          firstConfirmationHeader
        );
        await bridgeMock.setConfirmations(quote.transferConfirmations);
        const parsedAmount = ethers.parseEther(amount);
        const satAmount = weiToSat(parsedAmount);
        const btcTx = await generateRawTx(contract, quote, {
          scriptType: "p2pkh",
          amountOverride: satAmount,
        });

        await expect(
          contract
            .connect(usedLp)
            .refundPegOut(
              getBytes(quoteHash),
              btcTx,
              blockHeaderHash,
              partialMerkleTree,
              merkleBranchHashes
            )
        )
          .to.be.revertedWithCustomError(contract, "InsufficientAmount")
          .withArgs(satToWei(satAmount), quote.value);
      });
    }
  );

  it("revert if the btc tx isn't directed to the user's address", async () => {
    const { contract, quoteHash, quote, usedLp, bridgeMock } =
      await loadFixture(paidPegOutFixture);

    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();
    const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
      quote: quote,
      firstConfirmationSeconds: 100,
      nConfirmationSeconds: 600,
    });
    await bridgeMock.setHeaderByHash(blockHeaderHash, firstConfirmationHeader);
    await bridgeMock.setConfirmations(quote.transferConfirmations);
    const modifiedAddress = getTestBtcAddress("p2tr");
    const btcTx = await generateRawTx(contract, quote, {
      scriptType: "p2tr",
      addressOverride: modifiedAddress,
    });

    await expect(
      contract
        .connect(usedLp)
        .refundPegOut(
          getBytes(quoteHash),
          btcTx,
          blockHeaderHash,
          partialMerkleTree,
          merkleBranchHashes
        )
    )
      .to.be.revertedWithCustomError(contract, "InvalidDestination")
      .withArgs(quote.depositAddress, modifiedAddress);
  });

  // test the different combinations between address types and precisions
  BTC_ADDRESS_TYPES.forEach((type) => {
    AMOUNTS_TO_TEST_REFUND.forEach((amount) => {
      it(`execute refund successfully for a ${type} destination and ${amount} amount`, async () => {
        const { pegOutLp, contract, signers, bridgeMock } = await loadFixture(
          deployPegOutContractFixture
        );
        const contractAddress = await contract.getAddress();
        const user = signers[0];
        const quote = getTestPegoutQuote({
          lbcAddress: contractAddress,
          liquidityProvider: pegOutLp,
          refundAddress: user.address,
          value: ethers.parseEther(amount),
          destinationAddressType: type as BtcAddressType,
          productFeePercentage: 1,
        });
        const quoteTotal = totalValue(quote);
        const refundAmount =
          BigInt(quote.value) + BigInt(quote.gasFee) + BigInt(quote.callFee);

        const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
          getTestMerkleProof();
        const btcTx = await generateRawTx(contract, quote, {
          scriptType: type as BtcAddressType,
        });
        const quoteHash = await contract.hashPegOutQuote(quote);
        const signature = await pegOutLp.signMessage(getBytes(quoteHash));

        const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
          quote: quote,
          firstConfirmationSeconds: 100,
          nConfirmationSeconds: 600,
        });
        await bridgeMock.setHeaderByHash(
          blockHeaderHash,
          firstConfirmationHeader
        );
        await bridgeMock.setConfirmations(2);

        await expect(
          contract
            .connect(user)
            .depositPegOut(quote, signature, { value: quoteTotal })
        ).to.changeEtherBalances(
          [contractAddress, pegOutLp.address, user.address],
          [quoteTotal, 0, -quoteTotal]
        );

        const tx = contract
          .connect(pegOutLp)
          .refundPegOut(
            getBytes(quoteHash),
            btcTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
          );
        await expect(tx).to.changeEtherBalances(
          [contractAddress, pegOutLp.address, user.address],
          [-refundAmount, refundAmount, 0]
        );
        await expect(tx)
          .to.emit(contract, "PegOutRefunded")
          .withArgs(getBytes(quoteHash));
        await expect(tx)
          .to.emit(contract, "DaoContribution")
          .withArgs(pegOutLp.address, quote.productFeeAmount);
        await expect(contract.getCurrentContribution()).to.eventually.eq(
          quote.productFeeAmount
        );
        await expect(
          contract.isQuoteCompleted(getBytes(quoteHash)),
          "Should mark quote as completed"
        ).to.eventually.be.true;

        await expect(
          contract
            .connect(pegOutLp)
            .refundPegOut(
              getBytes(quoteHash),
              btcTx,
              blockHeaderHash,
              partialMerkleTree,
              merkleBranchHashes
            )
        )
          .to.be.revertedWithCustomError(contract, "QuoteAlreadyCompleted")
          .withArgs(getBytes(quoteHash));
      });

      it(`execute refund successfully for a ${type} destination and ${amount} truncated amount`, async () => {
        const { pegOutLp, contract, signers, bridgeMock } = await loadFixture(
          deployPegOutContractFixture
        );
        const contractAddress = await contract.getAddress();
        const user = signers[0];
        const quote = getTestPegoutQuote({
          lbcAddress: contractAddress,
          liquidityProvider: pegOutLp,
          refundAddress: user.address,
          value: ethers.parseEther(amount),
          destinationAddressType: type as BtcAddressType,
          productFeePercentage: 1,
        });
        const quoteTotal = totalValue(quote);
        const refundAmount =
          BigInt(quote.value) + BigInt(quote.gasFee) + BigInt(quote.callFee);

        const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
          getTestMerkleProof();
        const truncatedAmount =
          ethers.parseEther(amount) / WEI_TO_SAT_CONVERSION;
        const btcTx = await generateRawTx(contract, quote, {
          scriptType: type as BtcAddressType,
          amountOverride: truncatedAmount,
        });
        const quoteHash = await contract.hashPegOutQuote(quote);
        const signature = await pegOutLp.signMessage(getBytes(quoteHash));

        const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
          quote: quote,
          firstConfirmationSeconds: 100,
          nConfirmationSeconds: 600,
        });
        await bridgeMock.setHeaderByHash(
          blockHeaderHash,
          firstConfirmationHeader
        );
        await bridgeMock.setConfirmations(2);

        await expect(
          contract
            .connect(user)
            .depositPegOut(quote, signature, { value: quoteTotal })
        ).to.changeEtherBalances(
          [contractAddress, pegOutLp.address, user.address],
          [quoteTotal, 0, -quoteTotal]
        );

        const tx = contract
          .connect(pegOutLp)
          .refundPegOut(
            getBytes(quoteHash),
            btcTx,
            blockHeaderHash,
            partialMerkleTree,
            merkleBranchHashes
          );
        await expect(tx).to.changeEtherBalances(
          [contractAddress, pegOutLp.address, user.address],
          [-refundAmount, refundAmount, 0]
        );
        await expect(tx)
          .to.emit(contract, "PegOutRefunded")
          .withArgs(getBytes(quoteHash));
        await expect(tx)
          .to.emit(contract, "DaoContribution")
          .withArgs(pegOutLp.address, quote.productFeeAmount);
        await expect(contract.getCurrentContribution()).to.eventually.eq(
          quote.productFeeAmount
        );
        await expect(
          contract.isQuoteCompleted(getBytes(quoteHash)),
          "Should mark quote as completed"
        ).to.eventually.be.true;

        await expect(
          contract
            .connect(pegOutLp)
            .refundPegOut(
              getBytes(quoteHash),
              btcTx,
              blockHeaderHash,
              partialMerkleTree,
              merkleBranchHashes
            )
        )
          .to.be.revertedWithCustomError(contract, "QuoteAlreadyCompleted")
          .withArgs(getBytes(quoteHash));
      });
    });
  });

  it("execute refund successfully and penalize for being expired by time", async () => {
    const {
      contract,
      quote,
      bridgeMock,
      usedLp,
      quoteHash,
      collateralManagement,
    } = await loadFixture(paidPegOutFixture);
    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();
    const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
      quote: quote,
      firstConfirmationSeconds: 100,
      nConfirmationSeconds: 600,
    });
    await bridgeMock.setHeaderByHash(blockHeaderHash, firstConfirmationHeader);
    await bridgeMock.setConfirmations(2);
    const btcTx = await generateRawTx(contract, quote);
    const latestBlock = await ethers.provider.getBlock("latest");
    const interval =
      BigInt(quote.expireDate) - BigInt(latestBlock?.timestamp ?? 0) + 1n;
    await mine(2, { interval });

    const tx = contract
      .connect(usedLp)
      .refundPegOut(
        getBytes(quoteHash),
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
    await expect(tx)
      .to.emit(contract, "PegOutRefunded")
      .withArgs(getBytes(quoteHash));
    await expect(tx)
      .to.emit(contract, "DaoContribution")
      .withArgs(usedLp.address, quote.productFeeAmount);
    await expect(contract.getCurrentContribution()).to.eventually.eq(
      quote.productFeeAmount
    );
    await expect(tx)
      .to.emit(collateralManagement, "Penalized")
      .withArgs(
        usedLp.address,
        usedLp.address,
        getBytes(quoteHash),
        ProviderType.PegOut,
        quote.penaltyFee,
        getRewardForQuote(quote, COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE)
      );
  });

  it("execute refund successfully and penalize for being expired by blocks", async () => {
    const {
      contract,
      quote,
      bridgeMock,
      usedLp,
      quoteHash,
      collateralManagement,
    } = await loadFixture(paidPegOutFixture);
    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();
    const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
      quote: quote,
      firstConfirmationSeconds: 100,
      nConfirmationSeconds: 600,
    });
    await bridgeMock.setHeaderByHash(blockHeaderHash, firstConfirmationHeader);
    await bridgeMock.setConfirmations(2);
    const btcTx = await generateRawTx(contract, quote);
    await mineUpTo(BigInt(quote.expireBlock) + 1n);

    const tx = contract
      .connect(usedLp)
      .refundPegOut(
        getBytes(quoteHash),
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
    await expect(tx)
      .to.emit(contract, "PegOutRefunded")
      .withArgs(getBytes(quoteHash));
    await expect(tx)
      .to.emit(contract, "DaoContribution")
      .withArgs(usedLp.address, quote.productFeeAmount);
    await expect(contract.getCurrentContribution()).to.eventually.eq(
      quote.productFeeAmount
    );
    await expect(tx)
      .to.emit(collateralManagement, "Penalized")
      .withArgs(
        usedLp.address,
        usedLp.address,
        getBytes(quoteHash),
        ProviderType.PegOut,
        quote.penaltyFee,
        getRewardForQuote(quote, COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE)
      );
  });

  it("execute refund successfully and penalize for sending btc after expected first confirmation", async () => {
    const {
      contract,
      quote,
      bridgeMock,
      usedLp,
      quoteHash,
      collateralManagement,
    } = await loadFixture(paidPegOutFixture);
    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();

    const firstConfirmationSeconds =
      Number(quote.transferTime) + PEGOUT_CONSTANTS.TEST_BTC_BLOCK_TIME + 500;
    const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
      quote: quote,
      firstConfirmationSeconds,
      nConfirmationSeconds: firstConfirmationSeconds * 2,
    });
    await bridgeMock.setHeaderByHash(blockHeaderHash, firstConfirmationHeader);
    await bridgeMock.setConfirmations(2);
    const btcTx = await generateRawTx(contract, quote);

    const tx = contract
      .connect(usedLp)
      .refundPegOut(
        getBytes(quoteHash),
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
    await expect(tx)
      .to.emit(contract, "PegOutRefunded")
      .withArgs(getBytes(quoteHash));
    await expect(tx)
      .to.emit(contract, "DaoContribution")
      .withArgs(usedLp.address, quote.productFeeAmount);
    await expect(contract.getCurrentContribution()).to.eventually.eq(
      quote.productFeeAmount
    );
    await expect(tx)
      .to.emit(collateralManagement, "Penalized")
      .withArgs(
        usedLp.address,
        usedLp.address,
        getBytes(quoteHash),
        ProviderType.PegOut,
        quote.penaltyFee,
        getRewardForQuote(quote, COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE)
      );
  });

  it("revert if it can't extract the firstConfirmationHeader", async () => {
    const { contract, quote, bridgeMock, usedLp, quoteHash } =
      await loadFixture(paidPegOutFixture);
    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();
    await bridgeMock.setHeaderByHash(blockHeaderHash, "0x");
    await bridgeMock.setConfirmations(2);
    const btcTx = await generateRawTx(contract, quote);

    await expect(
      contract
        .connect(usedLp)
        .refundPegOut(
          getBytes(quoteHash),
          btcTx,
          blockHeaderHash,
          partialMerkleTree,
          merkleBranchHashes
        )
    )
      .to.be.revertedWithCustomError(contract, "EmptyBlockHeader")
      .withArgs(getBytes(blockHeaderHash));
  });
});
