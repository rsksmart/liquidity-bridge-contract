import hre from "hardhat";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployContract } from "../scripts/deployment-utils/utils";
import { deployLbcWithProvidersFixture } from "./utils/fixtures";
import { createBalanceDifferenceAssertion } from "./utils/asserts";
import { getBytes } from "ethers";
import { getTestPeginQuote } from "./utils/quotes";

describe("LiquidityBridgeContractV2 liquidity management should", () => {
  it("match LP address with address retrieved from ecrecover", async () => {
    const { lbc, liquidityProviders } = await loadFixture(
      deployLbcWithProvidersFixture
    );

    const deploymentInfo = await deployContract(
      "SignatureValidator",
      hre.network.name
    );
    const signatureValidator = await ethers.getContractAt(
      "SignatureValidator",
      deploymentInfo.address
    );

    const provider = liquidityProviders[0];
    const destinationAddress = await ethers
      .getSigners()
      .then((accounts) => accounts[0].address);
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: destinationAddress,
      value: ethers.parseEther("0.5"),
    });

    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);
    const signatureAddress = ethers.verifyMessage(quoteHash, signature);
    const validSignature = await signatureValidator.verify(
      provider.signer.address,
      quoteHash,
      signature
    );

    expect(signatureAddress).to.be.equal(provider.signer.address);
    expect(validSignature).to.be.eq(true);
  });
  it("fail when withdraw amount greater than the sender balance", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const provider = fixtureResult.liquidityProviders[0];
    let lbc = fixtureResult.lbc;

    lbc = lbc.connect(provider.signer);
    const depositTx = await lbc.deposit({ value: "100000000" });
    await depositTx.wait();
    const firstWithdrawTx = lbc.withdraw("999999999999999");
    await expect(firstWithdrawTx).to.be.revertedWith("LBC019");
    const secondWithdrawTx = lbc.withdraw("100000000");
    await expect(secondWithdrawTx).not.to.be.reverted;
  });

  it("deposit a value to increase balance of liquidity provider", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const provider = fixtureResult.liquidityProviders[1];
    const value = 100000000n;
    let lbc = fixtureResult.lbc;
    lbc = lbc.connect(provider.signer);

    const balanceAssertion = await createBalanceDifferenceAssertion({
      source: lbc,
      address: provider.signer.address,
      expectedDiff: value,
      message: "Incorrect LP balance after deposit",
    });
    const tx = await lbc.deposit({ value });
    await expect(tx)
      .to.emit(lbc, "BalanceIncrease")
      .withArgs(provider.signer.address, value);
    await balanceAssertion();
  });
});
