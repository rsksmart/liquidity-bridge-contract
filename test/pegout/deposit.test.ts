import {
  loadFixture,
  mine,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {
  getBtcPaymentBlockHeaders,
  getTestPegoutQuote,
  totalValue,
} from "../utils/quotes";
import { deployPegOutContractFixture } from "./fixtures";
import { ethers } from "hardhat";
import { expect } from "chai";
import { generateRawTx, getTestMerkleProof } from "../utils/btc";
import { getBytes, Interface } from "ethers";
import { PEGOUT_CONSTANTS } from "../utils/constants";

describe("PegOutContract depositPegOut function should", () => {
  const anyNumber = (value: unknown) =>
    typeof value === "bigint" || typeof value === "number";
  const matchSelector = (iface: Interface, error: string) => (value: unknown) =>
    value === iface.getError(error)?.selector;
  it("revert if the LP does not have collateral", async function () {
    const { contract, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const notLp = signers[3];
    const value = ethers.parseEther("1.03");
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: notLp,
      refundAddress: user.address,
      value,
    });
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await notLp.signMessage(getBytes(quoteHash));
    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: totalValue(quote) })
    )
      .to.be.revertedWithCustomError(contract, "ProviderNotRegistered")
      .withArgs(notLp.address);
  });

  it("revert if the LP does't support peg out", async function () {
    const { contract, pegInLp, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1.03");
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: pegInLp,
      refundAddress: user.address,
      value,
    });
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await pegInLp.signMessage(getBytes(quoteHash));
    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: totalValue(quote) })
    )
      .to.be.revertedWithCustomError(contract, "ProviderNotRegistered")
      .withArgs(pegInLp.address);
  });

  it("revert the amount is not enough", async function () {
    const { contract, fullLp, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1.03");
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: fullLp,
      refundAddress: user.address,
      value,
    });
    const sent = totalValue(quote) - 1n;
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await fullLp.signMessage(getBytes(quoteHash));
    await expect(
      contract.connect(user).depositPegOut(quote, signature, { value: sent })
    )
      .to.be.revertedWithCustomError(contract, "InsufficientAmount")
      .withArgs(sent, totalValue(quote));
  });

  it("revert if the quote is expired by date", async function () {
    const { contract, fullLp, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1");
    const quoteDepositDateExpired = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: fullLp,
      refundAddress: user.address,
      value,
    });
    const now = Math.floor(Date.now() / 1000);
    const quoteExpireDateExpired = structuredClone(quoteDepositDateExpired);
    quoteDepositDateExpired.depositDateLimit = now - 10000;
    quoteExpireDateExpired.expireDate = now - 1000;
    const firstQuoteSignature = await contract
      .hashPegOutQuote(quoteDepositDateExpired)
      .then((quoteHash) => fullLp.signMessage(getBytes(quoteHash)));
    const secondQuoteSignature = await contract
      .hashPegOutQuote(quoteExpireDateExpired)
      .then((quoteHash) => fullLp.signMessage(getBytes(quoteHash)));
    await expect(
      contract
        .connect(user)
        .depositPegOut(quoteDepositDateExpired, firstQuoteSignature, {
          value: totalValue(quoteDepositDateExpired),
        })
    )
      .to.be.revertedWithCustomError(contract, "QuoteExpiredByTime")
      .withArgs(
        quoteDepositDateExpired.depositDateLimit,
        quoteDepositDateExpired.expireDate
      );
    await expect(
      contract
        .connect(user)
        .depositPegOut(quoteExpireDateExpired, secondQuoteSignature, {
          value: totalValue(quoteExpireDateExpired),
        })
    )
      .to.be.revertedWithCustomError(contract, "QuoteExpiredByTime")
      .withArgs(
        quoteExpireDateExpired.depositDateLimit,
        quoteExpireDateExpired.expireDate
      );
  });

  it("revert if the quote is expired by blocks", async function () {
    const { contract, fullLp, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1.03");
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: fullLp,
      refundAddress: user.address,
      value,
    });
    const latestBlock = await ethers.provider.getBlockNumber();
    quote.expireBlock = latestBlock + 3;
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await fullLp.signMessage(getBytes(quoteHash));
    await mine(3);
    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: totalValue(quote) })
    )
      .to.be.revertedWithCustomError(contract, "QuoteExpiredByBlocks")
      .withArgs(quote.expireBlock);
  });

  it("revert if the signature is invalid", async function () {
    const { contract, fullLp, pegOutLp, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1.03");
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: pegOutLp,
      refundAddress: user.address,
      value,
    });
    const quoteHash = await contract.hashPegOutQuote(quote);
    const otherSignature = await fullLp.signMessage(getBytes(quoteHash));
    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, otherSignature, { value: totalValue(quote) })
    )
      .to.be.revertedWithCustomError(contract, "IncorrectSignature")
      .withArgs(pegOutLp.address, quoteHash, otherSignature);
  });

  it("revert if the quote was already completed successfully", async function () {
    const { contract, pegOutLp, bridgeMock, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1.03");
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: pegOutLp,
      refundAddress: user.address,
      value,
    });
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await pegOutLp.signMessage(getBytes(quoteHash));

    const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
      quote: quote,
      firstConfirmationSeconds: 100,
      nConfirmationSeconds: 600,
    });
    const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
      getTestMerkleProof();
    await bridgeMock.setHeaderByHash(blockHeaderHash, firstConfirmationHeader);

    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: totalValue(quote) })
    ).not.to.be.reverted;

    const btcTx = await generateRawTx(contract, quote);
    await expect(
      contract
        .connect(pegOutLp)
        .refundPegOut(
          quoteHash,
          btcTx,
          blockHeaderHash,
          partialMerkleTree,
          merkleBranchHashes
        )
    ).not.to.be.reverted;
    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: totalValue(quote) })
    )
      .to.be.revertedWithCustomError(contract, "QuoteAlreadyCompleted")
      .withArgs(quoteHash);
  });

  it("revert if the quote was already paid", async function () {
    const { contract, pegOutLp, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1.03");
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: pegOutLp,
      refundAddress: user.address,
      value,
    });
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await pegOutLp.signMessage(getBytes(quoteHash));
    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: totalValue(quote) })
    ).not.to.be.reverted;
    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: totalValue(quote) })
    )
      .to.be.revertedWithCustomError(contract, "QuoteAlreadyRegistered")
      .withArgs(quoteHash);
  });

  it("receive peg out deposit successfully without paying change", async function () {
    const { contract, pegOutLp, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1.03");
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: pegOutLp,
      refundAddress: user.address,
      value,
    });
    const paidAmount = totalValue(quote) + ethers.parseEther("0.00000009"); // lest than dust threshold
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await pegOutLp.signMessage(getBytes(quoteHash));
    const tx = contract
      .connect(user)
      .depositPegOut(quote, signature, { value: paidAmount });
    await expect(tx)
      .to.emit(contract, "PegOutDeposit")
      .withArgs(quoteHash, user.address, paidAmount, anyNumber);
    await expect(tx).not.to.emit(contract, "PegOutChangePaid");
    await expect(tx).to.changeEtherBalances(
      [user, contract],
      [-paidAmount, paidAmount]
    );
    await expect(
      contract.isQuoteCompleted(quoteHash),
      "Deposit should not mark quote as completed"
    ).to.eventually.be.false;
  });

  it("receive peg out deposit successfully paying change", async function () {
    const { contract, pegOutLp, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1.03");
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: pegOutLp,
      refundAddress: user.address,
      value,
    });
    const quoteValue = totalValue(quote);
    const paidAmount = quoteValue + PEGOUT_CONSTANTS.TEST_DUST_THRESHOLD;
    const changeAmount = paidAmount - quoteValue;
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await pegOutLp.signMessage(getBytes(quoteHash));
    const tx = contract
      .connect(user)
      .depositPegOut(quote, signature, { value: paidAmount });
    await expect(tx)
      .to.emit(contract, "PegOutDeposit")
      .withArgs(quoteHash, user.address, paidAmount, anyNumber);
    await expect(tx)
      .to.emit(contract, "PegOutChangePaid")
      .withArgs(quoteHash, user.address, changeAmount);
    await expect(tx).to.changeEtherBalances(
      [user, contract],
      [-quoteValue, quoteValue]
    );
    await expect(
      contract.isQuoteCompleted(quoteHash),
      "Deposit should not mark quote as completed"
    ).to.eventually.be.false;
  });

  it("revert if change payment fails", async function () {
    const { contract, fullLp, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1");
    const PegOutChangeReceiver = await ethers.deployContract(
      "PegOutChangeReceiver"
    );
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: fullLp,
      refundAddress: await PegOutChangeReceiver.getAddress(),
      value,
    });
    const paidAmount = ethers.parseEther("1.5");
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await fullLp.signMessage(getBytes(quoteHash));
    await PegOutChangeReceiver.setFail(true).then((tx) => tx.wait());
    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: paidAmount })
    )
      .to.be.revertedWithCustomError(contract, "PaymentFailed")
      .withArgs(
        quote.rskRefundAddress,
        anyNumber,
        matchSelector(PegOutChangeReceiver.interface, "SomeError")
      );
  });

  it("revert if change payment has reentrancy", async function () {
    const { contract, fullLp, signers } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const value = ethers.parseEther("1");
    const PegOutChangeReceiver = await ethers.deployContract(
      "PegOutChangeReceiver"
    );
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      liquidityProvider: fullLp,
      refundAddress: await PegOutChangeReceiver.getAddress(),
      value,
    });
    const paidAmount = ethers.parseEther("1.5");
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await fullLp.signMessage(getBytes(quoteHash));
    await PegOutChangeReceiver.setPegOut(quote, signature).then((tx) =>
      tx.wait()
    );
    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: paidAmount })
    )
      .to.be.revertedWithCustomError(contract, "PaymentFailed")
      .withArgs(
        quote.rskRefundAddress,
        anyNumber,
        matchSelector(contract.interface, "ReentrancyGuardReentrantCall")
      );
  });
});
