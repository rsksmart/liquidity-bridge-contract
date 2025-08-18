import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployPegInContractFixture } from "./fixtures";
import { ethers } from "hardhat";
import { expect } from "chai";
import { getTestPeginQuote } from "../utils/quotes";
import { PegInStates } from "../utils/constants";
import { matchAnyNumber } from "../utils/matchers";

describe("PegInContract callForUser function should", () => {
  it("execute call on behalf of the user using contract balance", async () => {
    const { contract, pegInLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: pegInLp,
      value: ethers.parseEther("0.6"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });

    const quoteHash = await contract.hashPegInQuote(quote);
    await expect(
      contract.connect(pegInLp).deposit({ value: ethers.parseEther("1") })
    ).not.to.be.reverted;

    const tx = contract.connect(pegInLp).callForUser(quote, { value: 0 });
    await expect(tx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        pegInLp.address,
        user.address,
        ethers.getBytes(quoteHash),
        quote.gasLimit,
        quote.value,
        "0x",
        true
      );
    await expect(tx).to.changeEtherBalances(
      [user, pegInLp, lbcAddress],
      [ethers.parseEther("0.6"), 0n, -ethers.parseEther("0.6")]
    );
    await expect(contract.getBalance(pegInLp)).to.eventually.eq(
      ethers.parseEther("0.4")
    );
    await expect(
      contract.getQuoteStatus(ethers.getBytes(quoteHash))
    ).to.eventually.eq(PegInStates.CALL_DONE);
  });
  it("execute call on behalf of the user using the value of the transaction", async () => {
    const { contract, pegInLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: pegInLp,
      value: ethers.parseEther("0.6"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });

    const quoteHash = await contract.hashPegInQuote(quote);
    const tx = contract
      .connect(pegInLp)
      .callForUser(quote, { value: ethers.parseEther("1") });
    await expect(tx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        pegInLp.address,
        user.address,
        ethers.getBytes(quoteHash),
        quote.gasLimit,
        quote.value,
        "0x",
        true
      );
    await expect(tx).to.changeEtherBalances(
      [user, pegInLp, lbcAddress],
      [
        ethers.parseEther("0.6"),
        -ethers.parseEther("1"),
        ethers.parseEther("0.4"),
      ]
    );
    await expect(contract.getBalance(pegInLp)).to.eventually.eq(
      ethers.parseEther("0.4")
    );
    await expect(
      contract.getQuoteStatus(ethers.getBytes(quoteHash))
    ).to.eventually.eq(PegInStates.CALL_DONE);
  });
  it("execute call on behalf of the user using contract balance and the value of the transaction", async () => {
    const { contract, pegInLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: pegInLp,
      value: ethers.parseEther("0.6"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });

    const quoteHash = await contract.hashPegInQuote(quote);
    await expect(
      contract.connect(pegInLp).deposit({ value: ethers.parseEther("0.3") })
    ).not.to.be.reverted;

    const tx = contract
      .connect(pegInLp)
      .callForUser(quote, { value: ethers.parseEther("0.4") });
    await expect(tx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        pegInLp.address,
        user.address,
        ethers.getBytes(quoteHash),
        quote.gasLimit,
        quote.value,
        "0x",
        true
      );
    await expect(tx).to.changeEtherBalances(
      [user, pegInLp, lbcAddress],
      [
        ethers.parseEther("0.6"),
        -ethers.parseEther("0.4"),
        -ethers.parseEther("0.2"),
      ]
    );
    await expect(contract.getBalance(pegInLp)).to.eventually.eq(
      ethers.parseEther("0.1")
    );
    await expect(
      contract.getQuoteStatus(ethers.getBytes(quoteHash))
    ).to.eventually.eq(PegInStates.CALL_DONE);
  });
  it("send RBTC to an EOA successfully", async () => {
    const { contract, fullLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const lbcAddress = await contract.getAddress();
    const user = signers[0];
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("0.5"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });

    const quoteHash = await contract.hashPegInQuote(quote);
    const tx = contract
      .connect(fullLp)
      .callForUser(quote, { value: ethers.parseEther("0.5") });
    await expect(tx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        fullLp.address,
        user.address,
        ethers.getBytes(quoteHash),
        quote.gasLimit,
        quote.value,
        "0x",
        true
      );
    await expect(tx).to.changeEtherBalances(
      [user, fullLp, lbcAddress],
      [ethers.parseEther("0.5"), -ethers.parseEther("0.5"), 0n]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
    await expect(
      contract.getQuoteStatus(ethers.getBytes(quoteHash))
    ).to.eventually.eq(PegInStates.CALL_DONE);
  });
  it("send RBTC to a smart contract successfully", async () => {
    const { contract, fullLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const user = signers[1];
    const lbcAddress = await contract.getAddress();
    const MockFactory = await ethers.getContractFactory("Mock");
    const mockContract = await MockFactory.deploy();
    const data = mockContract.interface.encodeFunctionData("set", [5n]);
    const mockAddress = await mockContract.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      data,
      liquidityProvider: fullLp,
      value: ethers.parseEther("0.7"),
      destinationAddress: mockAddress,
      refundAddress: user.address,
    });
    const quoteHash = await contract.hashPegInQuote(quote);

    await expect(mockContract.check()).to.eventually.eq(0n);
    const tx = contract
      .connect(fullLp)
      .callForUser(quote, { value: ethers.parseEther("0.7") });
    await expect(tx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        fullLp.address,
        mockAddress,
        ethers.getBytes(quoteHash),
        quote.gasLimit,
        quote.value,
        data,
        true
      );
    await expect(tx).to.changeEtherBalances(
      [mockAddress, fullLp, lbcAddress],
      [ethers.parseEther("0.7"), -ethers.parseEther("0.7"), 0n]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(0n);
    await expect(
      contract.getQuoteStatus(ethers.getBytes(quoteHash))
    ).to.eventually.eq(PegInStates.CALL_DONE);
    await expect(mockContract.check()).to.eventually.eq(5n);
  });
  it("execute an unsuccessful call", async () => {
    const { contract, fullLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const user = signers[1];
    const lbcAddress = await contract.getAddress();
    const MockFactory = await ethers.getContractFactory("Mock");
    const mockContract = await MockFactory.deploy();
    const data = mockContract.interface.encodeFunctionData("fail");
    const mockAddress = await mockContract.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      data,
      liquidityProvider: fullLp,
      value: ethers.parseEther("0.6"),
      destinationAddress: mockAddress,
      refundAddress: user.address,
    });
    const quoteHash = await contract.hashPegInQuote(quote);
    const tx = contract
      .connect(fullLp)
      .callForUser(quote, { value: ethers.parseEther("0.6") });
    await expect(tx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        fullLp.address,
        mockAddress,
        ethers.getBytes(quoteHash),
        quote.gasLimit,
        quote.value,
        data,
        false
      );
    await expect(tx).to.changeEtherBalances(
      [mockAddress, fullLp, lbcAddress],
      [0n, -ethers.parseEther("0.6"), ethers.parseEther("0.6")]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(
      ethers.parseEther("0.6")
    );
    await expect(
      contract.getQuoteStatus(ethers.getBytes(quoteHash))
    ).to.eventually.eq(PegInStates.CALL_DONE);
  });
  it("revert if LP is not registered", async () => {
    const { contract, pegOutLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const user = signers[1];
    const lbcAddress = await contract.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: pegOutLp,
      value: ethers.parseEther("0.6"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    const tx = contract
      .connect(pegOutLp)
      .callForUser(quote, { value: ethers.parseEther("0.6") });
    await expect(tx)
      .to.be.revertedWithCustomError(contract, "ProviderNotRegistered")
      .withArgs(pegOutLp.address);
  });
  it("revert quote doesn't belong to LP", async () => {
    const { contract, pegInLp, fullLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const user = signers[1];
    const lbcAddress = await contract.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: fullLp,
      value: ethers.parseEther("0.6"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    const tx = contract
      .connect(pegInLp)
      .callForUser(quote, { value: ethers.parseEther("0.6") });
    await expect(tx)
      .to.be.revertedWithCustomError(contract, "InvalidSender")
      .withArgs(fullLp.address, pegInLp.address);
  });
  it("revert balance of the contract and transaction value is not enough for the quote", async () => {
    const { contract, pegInLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const user = signers[1];
    const lbcAddress = await contract.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: pegInLp,
      value: ethers.parseEther("0.6"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    await expect(
      contract.connect(pegInLp).deposit({ value: ethers.parseEther("0.3") })
    ).not.to.be.reverted;
    const tx = contract
      .connect(pegInLp)
      .callForUser(quote, { value: ethers.parseEther("0.2") });
    await expect(tx)
      .to.be.revertedWithCustomError(contract, "InsufficientAmount")
      .withArgs(ethers.parseEther("0.5"), ethers.parseEther("0.6"));
  });
  it("revert if the quote was already processed", async () => {
    const { contract, pegInLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const user = signers[1];
    const lbcAddress = await contract.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: pegInLp,
      value: ethers.parseEther("0.6"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    const quoteHash = await contract.hashPegInQuote(quote);
    await expect(
      contract
        .connect(pegInLp)
        .callForUser(quote, { value: ethers.parseEther("0.6") })
    ).not.to.be.reverted;
    await expect(
      contract
        .connect(pegInLp)
        .callForUser(quote, { value: ethers.parseEther("0.6") })
    )
      .to.be.revertedWithCustomError(contract, "QuoteAlreadyProcessed")
      .withArgs(ethers.getBytes(quoteHash));
  });
  it("revert if gas of the callForUser transaction is not enough", async () => {
    const { contract, pegInLp, signers } = await loadFixture(
      deployPegInContractFixture
    );
    const user = signers[1];
    const lbcAddress = await contract.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress,
      liquidityProvider: pegInLp,
      value: ethers.parseEther("0.6"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    const callGasCost = 35_000n;
    const estimatedGas = await contract
      .connect(pegInLp)
      .callForUser.estimateGas(quote, {
        value: ethers.parseEther("0.6"),
      });
    await expect(
      contract.connect(pegInLp).callForUser(quote, {
        value: ethers.parseEther("0.6"),
        gasLimit: estimatedGas - callGasCost,
      })
    )
      .to.be.revertedWithCustomError(contract, "InsufficientGas")
      .withArgs(matchAnyNumber, BigInt(quote.gasLimit) + callGasCost);
  });
  it("not allow reentrancy", async () => {
    const { contract, fullLp } = await loadFixture(deployPegInContractFixture);
    const lbcAddress = await contract.getAddress();

    const ReentrancyCaller = await ethers.getContractFactory(
      "ReentrancyCaller"
    );
    const reentrancyCallerContract = await ReentrancyCaller.deploy();
    const reentrantData = contract.interface.encodeFunctionData("withdraw", [
      ethers.parseEther("0.0001"),
    ]);
    const callerAddress = await reentrancyCallerContract.getAddress();
    const data =
      reentrancyCallerContract.interface.encodeFunctionData("reentrantCall");

    const contractQuote = getTestPeginQuote({
      lbcAddress,
      data,
      liquidityProvider: fullLp,
      value: ethers.parseEther("0.5"),
      destinationAddress: callerAddress,
      refundAddress: fullLp.address,
    });
    contractQuote.gasLimit = BigInt(contractQuote.gasLimit) * 3n;
    const quoteHash = await contract.hashPegInQuote(contractQuote);
    const reentrancySelector = contract.interface.getError(
      "ReentrancyGuardReentrantCall"
    )?.selector;

    await expect(reentrancyCallerContract.setData(reentrantData)).not.to.be
      .reverted;
    await expect(
      contract.connect(fullLp).deposit({ value: ethers.parseEther("10") })
    ).not.to.be.reverted;
    const tx = contract.connect(fullLp).callForUser(contractQuote);
    await expect(tx)
      .to.emit(contract, "CallForUser")
      .withArgs(
        fullLp.address,
        callerAddress,
        ethers.getBytes(quoteHash),
        contractQuote.gasLimit,
        contractQuote.value,
        data,
        true
      );
    await expect(tx)
      .to.emit(reentrancyCallerContract, "ReentrancyReverted")
      .withArgs(reentrancySelector);
    await expect(tx).to.changeEtherBalances(
      [callerAddress, fullLp, lbcAddress],
      [contractQuote.value, 0n, -BigInt(contractQuote.value)]
    );
    await expect(contract.getBalance(fullLp)).to.eventually.eq(
      ethers.parseEther("9.5")
    );
    await expect(
      contract.getQuoteStatus(ethers.getBytes(quoteHash))
    ).to.eventually.eq(PegInStates.CALL_DONE);
    await expect(reentrancyCallerContract.getRevertReason()).to.eventually.eq(
      reentrancySelector
    );
  });
});
