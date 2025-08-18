import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployPegInContractFixture } from "./fixtures";
import { ethers } from "hardhat";
import { expect } from "chai";

describe("PegInContract deposit function should", () => {
  it("only allow liquidity providers to deposit", async function () {
    const { contract, pegInLp, pegOutLp, fullLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    await expect(
      contract.connect(signers[0]).deposit({ value: ethers.parseEther("1") })
    )
      .to.be.revertedWithCustomError(contract, "ProviderNotRegistered")
      .withArgs(signers[0].address);
    await expect(
      contract.connect(pegOutLp).deposit({ value: ethers.parseEther("1") })
    )
      .to.be.revertedWithCustomError(contract, "ProviderNotRegistered")
      .withArgs(pegOutLp.address);
    await expect(
      contract.connect(pegInLp).deposit({ value: ethers.parseEther("1") })
    ).not.to.be.reverted;
    await expect(
      contract.connect(fullLp).deposit({ value: ethers.parseEther("1") })
    ).not.to.be.reverted;
  });
  it("increase balance properly", async function () {
    const { contract, fullLp } = await loadFixture(deployPegInContractFixture);
    const value = ethers.parseEther("1");
    const tx = contract.connect(fullLp).deposit({ value });
    await expect(tx)
      .to.emit(contract, "BalanceIncrease")
      .withArgs(fullLp.address, value);
    await expect(tx).to.changeEtherBalances(
      [await contract.getAddress(), fullLp.address],
      [value, -value]
    );
    await expect(contract.getBalance(fullLp.address)).to.eventually.eq(value);
  });
  it("not emit event if amount is zero", async function () {
    const { contract, pegInLp } = await loadFixture(deployPegInContractFixture);
    const tx = contract.connect(pegInLp).deposit({ value: 0n });
    await expect(tx).not.to.emit(contract, "BalanceIncrease");
    await expect(tx).not.to.be.reverted;
    await expect(contract.getBalance(pegInLp.address)).to.eventually.eq(0n);
  });
});
