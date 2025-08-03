import {
  loadFixture,
  mine,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployPegOutContractFixture } from "./fixtures";
import { getTestPegoutQuote, totalValue } from "../utils/quotes";
import { ethers } from "hardhat";
import { getBytes } from "ethers";
import { expect } from "chai";
import { matchSelector, matchAnyNumber } from "../utils/matchers";
import { ProviderType } from "../utils/constants";

describe("PegOutContract refundUserPegOut function should", () => {
  it("revert if quote was not paid", async () => {
    const { contract, signers, fullLp } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      refundAddress: user.address,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1"),
    });
    const quoteHash = await contract.hashPegOutQuote(quote);
    await expect(contract.refundUserPegOut(getBytes(quoteHash)))
      .to.be.revertedWithCustomError(contract, "QuoteNotFound")
      .withArgs(getBytes(quoteHash));
  });

  it("revert if quote is not expired by blocks", async () => {
    const { contract, signers, fullLp } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      refundAddress: user.address,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1"),
    });

    const latestBlock = await ethers.provider.getBlock("latest");
    quote.expireDate = (latestBlock?.timestamp ?? 0) + 5;
    quote.expireBlock = (latestBlock?.number ?? 0) + 20;
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await fullLp.signMessage(getBytes(quoteHash));
    await expect(
      contract.depositPegOut(quote, signature, { value: totalValue(quote) })
    ).not.to.be.reverted;
    await mine(10, { interval: 1 });
    await expect(contract.refundUserPegOut(getBytes(quoteHash)))
      .to.be.revertedWithCustomError(contract, "QuoteNotExpired")
      .withArgs(getBytes(quoteHash));
  });

  it("revert if quote is not expired by date", async () => {
    const { contract, signers, fullLp } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      refundAddress: user.address,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1"),
    });

    const latestBlock = await ethers.provider.getBlock("latest");
    quote.expireBlock = (latestBlock?.number ?? 0) + 5;
    quote.expireDate = (latestBlock?.timestamp ?? 0) + 20;
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await fullLp.signMessage(getBytes(quoteHash));
    await expect(
      contract.depositPegOut(quote, signature, { value: totalValue(quote) })
    ).not.to.be.reverted;
    await mine(10, { interval: 1 });
    await expect(contract.refundUserPegOut(getBytes(quoteHash)))
      .to.be.revertedWithCustomError(contract, "QuoteNotExpired")
      .withArgs(getBytes(quoteHash));
  });

  it("revert if the payment to the user fails", async () => {
    const { contract, signers, fullLp } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const PegOutChangeReceiver = await ethers.deployContract(
      "PegOutChangeReceiver"
    );
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      refundAddress: await PegOutChangeReceiver.getAddress(),
      liquidityProvider: fullLp,
      value: ethers.parseEther("1"),
    });

    const latestBlock = await ethers.provider.getBlock("latest");
    quote.expireDate = (latestBlock?.timestamp ?? 0) + 20;
    quote.expireBlock = (latestBlock?.number ?? 0) + 5;
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await fullLp.signMessage(getBytes(quoteHash));

    await expect(PegOutChangeReceiver.setFail(true)).not.to.be.reverted;

    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: totalValue(quote) })
    ).not.to.be.reverted;

    await mine(5, { interval: 20 });

    await expect(contract.connect(user).refundUserPegOut(getBytes(quoteHash)))
      .to.be.revertedWithCustomError(contract, "PaymentFailed")
      .withArgs(
        quote.rskRefundAddress,
        matchAnyNumber,
        matchSelector(PegOutChangeReceiver.interface, "SomeError")
      );
  });

  it("not allow reentrancy", async () => {
    const { contract, signers, fullLp } = await loadFixture(
      deployPegOutContractFixture
    );
    const user = signers[0];
    const PegOutChangeReceiver = await ethers.deployContract(
      "PegOutChangeReceiver"
    );
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      refundAddress: await PegOutChangeReceiver.getAddress(),
      liquidityProvider: fullLp,
      value: ethers.parseEther("1"),
    });

    const latestBlock = await ethers.provider.getBlock("latest");
    quote.expireDate = (latestBlock?.timestamp ?? 0) + 20;
    quote.expireBlock = (latestBlock?.number ?? 0) + 5;
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await fullLp.signMessage(getBytes(quoteHash));

    await expect(PegOutChangeReceiver.setFail(false)).not.to.be.reverted;
    await expect(PegOutChangeReceiver.setPegOut(quote, signature)).not.to.be
      .reverted;
    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: totalValue(quote) })
    ).not.to.be.reverted;

    await mine(5, { interval: 20 });

    await expect(contract.connect(user).refundUserPegOut(getBytes(quoteHash)))
      .to.be.revertedWithCustomError(contract, "PaymentFailed")
      .withArgs(
        quote.rskRefundAddress,
        matchAnyNumber,
        matchSelector(contract.interface, "ReentrancyGuardReentrantCall")
      );
  });

  it("execute the refund and slash the liquidity provider", async () => {
    const { contract, signers, fullLp, collateralManagement } =
      await loadFixture(deployPegOutContractFixture);
    const user = signers[0];
    const quote = getTestPegoutQuote({
      lbcAddress: await contract.getAddress(),
      refundAddress: user.address,
      liquidityProvider: fullLp,
      value: ethers.parseEther("1"),
    });
    const totalQuoteValue = totalValue(quote);

    const latestBlock = await ethers.provider.getBlock("latest");
    quote.expireDate = (latestBlock?.timestamp ?? 0) + 20;
    quote.expireBlock = (latestBlock?.number ?? 0) + 5;
    const quoteHash = await contract.hashPegOutQuote(quote);
    const signature = await fullLp.signMessage(getBytes(quoteHash));

    await expect(
      contract
        .connect(user)
        .depositPegOut(quote, signature, { value: totalQuoteValue })
    ).not.to.be.reverted;

    await mine(5, { interval: 20 });

    const tx = contract.connect(user).refundUserPegOut(getBytes(quoteHash));

    await expect(tx)
      .to.emit(contract, "PegOutUserRefunded")
      .withArgs(getBytes(quoteHash), quote.rskRefundAddress, totalQuoteValue);
    await expect(tx)
      .to.emit(contract, "PegOutUserRefunded")
      .withArgs(getBytes(quoteHash), quote.rskRefundAddress, totalQuoteValue);
    await expect(tx, "Should call collateral management")
      .to.emit(collateralManagement, "Penalized")
      .withArgs(
        fullLp.address,
        getBytes(quoteHash),
        ProviderType.PegOut,
        quote.penaltyFee
      );
    await expect(tx).to.changeEtherBalances(
      [await contract.getAddress(), user.address],
      [-totalQuoteValue, totalQuoteValue]
    );
    await expect(
      contract.isQuoteCompleted(getBytes(quoteHash)),
      "Should mark quote as completed"
    ).to.be.eventually.true;
    await expect(
      contract.connect(user).refundUserPegOut(getBytes(quoteHash)),
      "Should remove quote from storage"
    )
      .to.be.revertedWithCustomError(contract, "QuoteNotFound")
      .withArgs(getBytes(quoteHash));
  });
});
