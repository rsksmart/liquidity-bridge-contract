import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployPegInContractFixture } from "./fixtures";
import { ethers } from "hardhat";
import { expect } from "chai";
import { matchAnyNumber, matchSelector } from "../utils/matchers";

describe("PegInContract withdraw function should", () => {
  it("not allow to withdraw more than the current balance", async function () {
    const { contract, fullLp } = await loadFixture(deployPegInContractFixture);
    const depositedAmount = ethers.parseEther("1");
    const withdrawAmount = ethers.parseEther("1.000000000000000001");
    await expect(contract.connect(fullLp).deposit({ value: depositedAmount }))
      .not.to.be.reverted;
    await expect(contract.connect(fullLp).withdraw(withdrawAmount))
      .to.be.revertedWithCustomError(contract, "NoBalance")
      .withArgs(withdrawAmount, depositedAmount);
  });
  it("allow to withdraw everything", async function () {
    const { contract, fullLp } = await loadFixture(deployPegInContractFixture);
    const balance = ethers.parseEther("1");
    await expect(contract.connect(fullLp).deposit({ value: balance })).not.to.be
      .reverted;
    const tx = contract.connect(fullLp).withdraw(balance);
    await expect(tx)
      .to.emit(contract, "BalanceDecrease")
      .withArgs(fullLp.address, balance);
    await expect(tx)
      .to.emit(contract, "Withdrawal")
      .withArgs(fullLp.address, balance);
    await expect(contract.getBalance(fullLp.address)).to.eventually.eq(0n);
  });
  it("decrease balance properly", async function () {
    const { contract, fullLp } = await loadFixture(deployPegInContractFixture);
    const balance = ethers.parseEther("1");
    const withdrawAmount = ethers.parseEther("0.2");
    await expect(contract.connect(fullLp).deposit({ value: balance })).not.to.be
      .reverted;
    const tx = contract.connect(fullLp).withdraw(withdrawAmount);
    await expect(tx)
      .to.emit(contract, "BalanceDecrease")
      .withArgs(fullLp.address, withdrawAmount);
    await expect(tx)
      .to.emit(contract, "Withdrawal")
      .withArgs(fullLp.address, withdrawAmount);
    await expect(contract.getBalance(fullLp.address)).to.eventually.eq(
      ethers.parseEther("0.8")
    );
  });
  it("revert if withdrawal fails", async function () {
    const { contract, owner, signers } = await loadFixture(
      deployPegInContractFixture
    );

    const CollateralManagementMock = await ethers.getContractFactory(
      "CollateralManagementMock"
    );
    const newCollateralManagement = await CollateralManagementMock.deploy();
    const WithdrawReceiver = await ethers.getContractFactory(
      "WithdrawReceiver"
    );
    const receiver = await WithdrawReceiver.deploy(await contract.getAddress());

    const withdrawAmount = ethers.parseEther("0.1");
    const receiverAddress = await receiver.getAddress();

    await expect(
      contract
        .connect(owner)
        .setCollateralManagement(await newCollateralManagement.getAddress())
    ).not.to.be.reverted;
    await expect(receiver.connect(signers[0]).setFail(true)).not.to.be.reverted;
    await expect(
      receiver.connect(signers[0]).deposit({ value: withdrawAmount })
    ).not.to.be.reverted;
    await expect(receiver.connect(signers[1]).withdraw(withdrawAmount))
      .to.be.revertedWithCustomError(contract, "PaymentFailed")
      .withArgs(
        receiverAddress,
        withdrawAmount,
        matchSelector(receiver.interface, "SomeError")
      );
  });

  it("not allow reentrancy", async function () {
    const { contract, owner, signers } = await loadFixture(
      deployPegInContractFixture
    );

    const CollateralManagementMock = await ethers.getContractFactory(
      "CollateralManagementMock"
    );
    const newCollateralManagement = await CollateralManagementMock.deploy();
    const WithdrawReceiver = await ethers.getContractFactory(
      "WithdrawReceiver"
    );
    const receiver = await WithdrawReceiver.deploy(await contract.getAddress());

    const withdrawAmount = ethers.parseEther("0.1");
    const receiverAddress = await receiver.getAddress();

    await expect(
      contract
        .connect(owner)
        .setCollateralManagement(await newCollateralManagement.getAddress())
    ).not.to.be.reverted;
    await expect(receiver.connect(signers[0]).setFail(false)).not.to.be
      .reverted;
    await expect(
      receiver.connect(signers[0]).deposit({ value: withdrawAmount })
    ).not.to.be.reverted;
    await expect(receiver.connect(signers[1]).withdraw(withdrawAmount))
      .to.be.revertedWithCustomError(contract, "PaymentFailed")
      .withArgs(
        receiverAddress,
        matchAnyNumber,
        matchSelector(contract.interface, "ReentrancyGuardReentrantCall")
      );
  });
});
