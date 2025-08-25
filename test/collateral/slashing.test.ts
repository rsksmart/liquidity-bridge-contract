import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployCollateralManagementWithRoles } from "./fixtures";
import { expect } from "chai";
import {
  getRewardForQuote,
  getTestPeginQuote,
  getTestPegoutQuote,
} from "../utils/quotes";
import hre, { ethers } from "hardhat";
import { randomBytes } from "crypto";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { Quotes } from "../../typechain-types/contracts/libraries";
import { CollateralManagementContract } from "../../typechain-types";
import { COLLATERAL_CONSTANTS, ProviderType } from "../utils/constants";
import { deployContract } from "../../scripts/deployment-utils/utils";

describe("CollateralManagementContract slashing functionality", () => {
  const BASE_COLLATERAL = ethers.parseEther("10");
  let quoteHash: string;
  let slasher: SignerWithAddress;
  let pegInQuote: Quotes.PegInQuoteStruct;
  let pegOutQuote: Quotes.PegOutQuoteStruct;
  let punisher: SignerWithAddress;
  let liquidityProvider: SignerWithAddress;
  let user: SignerWithAddress;
  let collateralManagement: CollateralManagementContract;
  let signers: SignerWithAddress[];

  beforeEach(async function () {
    const deploy = await loadFixture(deployCollateralManagementWithRoles);
    slasher = deploy.slasher;
    signers = deploy.signers;
    collateralManagement = deploy.collateralManagement;
    const address = await collateralManagement.getAddress();
    punisher = signers[0];
    liquidityProvider = signers[1];
    user = signers[2];
    quoteHash = "0x" + randomBytes(32).toString("hex");
    pegInQuote = getTestPeginQuote({
      lbcAddress: address,
      liquidityProvider: liquidityProvider,
      value: ethers.parseEther("1"),
      destinationAddress: user.address,
      refundAddress: user.address,
    });
    pegOutQuote = getTestPegoutQuote({
      lbcAddress: address,
      liquidityProvider: liquidityProvider,
      value: ethers.parseEther("1"),
      refundAddress: user.address,
    });
    await collateralManagement
      .connect(deploy.adder)
      .addPegInCollateralTo(liquidityProvider.address, {
        value: BASE_COLLATERAL,
      });
    await collateralManagement
      .connect(deploy.adder)
      .addPegOutCollateralTo(liquidityProvider.address, {
        value: BASE_COLLATERAL,
      });
  });
  describe("slashPegInCollateral function should", function () {
    it("only allow slasher role to slash collateral", async function () {
      await expect(
        collateralManagement
          .connect(signers.at(-1))
          .slashPegOutCollateral(punisher, pegOutQuote, quoteHash)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "AccessControlUnauthorizedAccount"
      );
      await expect(
        collateralManagement
          .connect(signers.at(-1))
          .slashPegInCollateral(punisher, pegInQuote, quoteHash)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "AccessControlUnauthorizedAccount"
      );
    });

    it("slash peg in collateral properly", async function () {
      const penalty = BigInt(pegInQuote.penaltyFee);
      const reward = getRewardForQuote(
        pegInQuote,
        COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE
      );
      await expect(
        collateralManagement.getPegInCollateral(liquidityProvider.address)
      ).to.eventually.eq(BASE_COLLATERAL);
      const tx = await collateralManagement
        .connect(slasher)
        .slashPegInCollateral(punisher, pegInQuote, quoteHash);
      await expect(tx)
        .to.emit(collateralManagement, "Penalized")
        .withArgs(
          liquidityProvider.address,
          punisher.address,
          quoteHash,
          ProviderType.PegIn,
          penalty,
          reward
        );
      await expect(
        collateralManagement.getPegInCollateral(liquidityProvider.address)
      ).to.eventually.eq(BASE_COLLATERAL - penalty);
      await expect(
        collateralManagement.getRewards(punisher.address)
      ).to.eventually.eq(reward);
      await expect(collateralManagement.getPenalties()).to.eventually.eq(
        penalty - reward
      );
    });

    it("slash peg out collateral properly", async function () {
      const penalty = BigInt(pegOutQuote.penaltyFee);
      const reward = getRewardForQuote(
        pegOutQuote,
        COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE
      );
      await expect(
        collateralManagement.getPegOutCollateral(liquidityProvider.address)
      ).to.eventually.eq(BASE_COLLATERAL);
      const tx = await collateralManagement
        .connect(slasher)
        .slashPegOutCollateral(punisher, pegOutQuote, quoteHash);
      await expect(tx)
        .to.emit(collateralManagement, "Penalized")
        .withArgs(
          liquidityProvider.address,
          punisher.address,
          quoteHash,
          ProviderType.PegOut,
          penalty,
          reward
        );
      await expect(
        collateralManagement.getPegOutCollateral(liquidityProvider.address)
      ).to.eventually.eq(BASE_COLLATERAL - penalty);
      await expect(
        collateralManagement.getRewards(punisher.address)
      ).to.eventually.eq(reward);
      await expect(collateralManagement.getPenalties()).to.eventually.eq(
        penalty - reward
      );
    });

    it("pay slash rewards properly", async function () {
      const pegInReward = getRewardForQuote(
        pegInQuote,
        COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE
      );
      const pegOutReward = getRewardForQuote(
        pegOutQuote,
        COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE
      );
      const pegInPenalty = BigInt(pegInQuote.penaltyFee);
      const pegOutPenalty = BigInt(pegOutQuote.penaltyFee);
      await expect(
        collateralManagement
          .connect(slasher)
          .slashPegInCollateral(punisher, pegInQuote, quoteHash)
      ).not.to.be.reverted;
      await expect(
        collateralManagement
          .connect(slasher)
          .slashPegOutCollateral(punisher, pegOutQuote, quoteHash)
      ).not.to.be.reverted;
      await expect(
        collateralManagement.getRewards(punisher.address)
      ).to.eventually.eq(pegInReward + pegOutReward);
      await expect(collateralManagement.getPenalties()).to.eventually.eq(
        pegInPenalty + pegOutPenalty - pegInReward - pegOutReward
      );
      const tx = await collateralManagement.connect(punisher).withdrawRewards();
      await expect(tx)
        .to.emit(collateralManagement, "RewardsWithdrawn")
        .withArgs(punisher.address, pegInReward + pegOutReward);
      await expect(tx).to.changeEtherBalances(
        [punisher.address, await collateralManagement.getAddress()],
        [pegInReward + pegOutReward, -pegInReward - pegOutReward]
      );
      await expect(
        collateralManagement.getRewards(punisher.address)
      ).to.eventually.eq(0n);
      await expect(collateralManagement.getPenalties()).to.eventually.eq(
        pegInPenalty + pegOutPenalty - pegInReward - pegOutReward
      );
    });

    it("revert if there is no reward to withdraw", async function () {
      await expect(
        collateralManagement
          .connect(slasher)
          .slashPegInCollateral(punisher, pegInQuote, quoteHash)
      ).not.to.be.reverted;
      await expect(
        collateralManagement
          .connect(slasher)
          .slashPegOutCollateral(punisher, pegOutQuote, quoteHash)
      ).not.to.be.reverted;
      await expect(collateralManagement.connect(slasher).withdrawRewards())
        .to.be.revertedWithCustomError(
          collateralManagement,
          "NothingToWithdraw"
        )
        .withArgs(slasher.address);
    });
    it("revert if withdraw external call fails", async function () {
      const deploymentInfo = await deployContract(
        "WalletMock",
        hre.network.name
      );
      const walletMock = await ethers.getContractAt(
        "WalletMock",
        deploymentInfo.address
      );
      const walletMockAddress = await walletMock.getAddress();
      const collateralManagementAddress =
        await collateralManagement.getAddress();
      await expect(
        collateralManagement
          .connect(slasher)
          .slashPegInCollateral(walletMockAddress, pegInQuote, quoteHash)
      ).not.to.be.reverted;
      await expect(
        collateralManagement
          .connect(slasher)
          .slashPegOutCollateral(walletMockAddress, pegOutQuote, quoteHash)
      ).not.to.be.reverted;
      const error = collateralManagement.interface.encodeErrorResult(
        "WithdrawalFailed",
        [
          walletMockAddress,
          await collateralManagement.getRewards(walletMockAddress),
        ]
      );
      await expect(walletMock.setRejectFunds(true)).not.to.be.reverted;
      await expect(
        walletMock.execute(
          collateralManagementAddress,
          0n,
          collateralManagement.interface.encodeFunctionData("withdrawRewards")
        )
      )
        .to.emit(walletMock, "TransactionRejected")
        .withArgs(collateralManagementAddress, 0n, error);
    });
  });
});
