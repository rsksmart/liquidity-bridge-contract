import { expect } from "chai";
import {
  loadFixture,
  mine,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {
  deployCollateralManagementWithProviders,
  deployCollateralManagementWithRoles,
} from "./fixtures";
import hre, { ethers } from "hardhat";
import {
  COLLATERAL_CONSTANTS,
  ProviderType,
  ZERO_ADDRESS,
} from "../utils/constants";
import { getEmptyPegInQuote, getEmptyPegOutQuote } from "../utils/quotes";
import { zeroPadBytes } from "ethers";
import { deployContract } from "../../scripts/deployment-utils/utils";

describe("CollateralManagementContract resign functionality", () => {
  describe("resign function should", function () {
    it("revert if the provider resigns twice", async function () {
      const { collateralManagement, pegInLp, pegOutLp, fullLp } =
        await loadFixture(deployCollateralManagementWithProviders);
      const providers = [pegInLp, pegOutLp, fullLp];
      for (const provider of providers) {
        await expect(collateralManagement.connect(provider).resign()).not.to.be
          .reverted;
        await expect(collateralManagement.connect(provider).resign())
          .to.be.revertedWithCustomError(
            collateralManagement,
            "AlreadyResigned"
          )
          .withArgs(provider.address);
      }
    });
    it("revert account is not registered for any operation", async function () {
      const { collateralManagement, signers } = await loadFixture(
        deployCollateralManagementWithProviders
      );
      const notProvider = signers[0];
      await expect(collateralManagement.connect(notProvider).resign())
        .to.be.revertedWithCustomError(
          collateralManagement,
          "ProviderNotRegistered"
        )
        .withArgs(notProvider.address);
    });
    it("allow providers to resign", async function () {
      const { collateralManagement, providers } = await loadFixture(
        deployCollateralManagementWithProviders
      );
      const collateralManagementAddress =
        await collateralManagement.getAddress();
      for (const provider of providers) {
        const signer = provider.signer;
        if (provider.pegIn) {
          await expect(
            collateralManagement.isRegistered(
              ProviderType.PegIn,
              signer.address
            )
          ).to.eventually.be.true;
          await expect(
            collateralManagement.isCollateralSufficient(
              ProviderType.PegIn,
              signer.address
            )
          ).to.eventually.be.true;
        }
        if (provider.pegOut) {
          await expect(
            collateralManagement.isRegistered(
              ProviderType.PegOut,
              signer.address
            )
          ).to.eventually.be.true;
          await expect(
            collateralManagement.isCollateralSufficient(
              ProviderType.PegOut,
              signer.address
            )
          ).to.eventually.be.true;
        }
        const tx = collateralManagement.connect(signer).resign();
        await expect(tx)
          .to.emit(collateralManagement, "Resigned")
          .withArgs(signer.address);
        await expect(tx).to.changeEtherBalances(
          [signer.address, collateralManagementAddress],
          [0, 0]
        );
        const block = await ethers.provider.getBlockNumber();
        const resignBlockNum = await collateralManagement.getResignationBlock(
          signer.address
        );
        expect(resignBlockNum).to.equal(block);
        if (provider.pegIn) {
          await expect(
            collateralManagement.isRegistered(
              ProviderType.PegIn,
              signer.address
            )
          ).to.eventually.be.false;
          await expect(
            collateralManagement.isCollateralSufficient(
              ProviderType.PegIn,
              signer.address
            )
          ).to.eventually.be.false;
        }
        if (provider.pegOut) {
          await expect(
            collateralManagement.isRegistered(
              ProviderType.PegOut,
              signer.address
            )
          ).to.eventually.be.false;
          await expect(
            collateralManagement.isCollateralSufficient(
              ProviderType.PegOut,
              signer.address
            )
          ).to.eventually.be.false;
        }
      }
    });
  });

  describe("withdrawCollateral function should", function () {
    it("revert if the provider is not registered", async function () {
      const { collateralManagement, signers } = await loadFixture(
        deployCollateralManagementWithProviders
      );
      const notProvider = signers[0];
      await expect(
        collateralManagement.connect(notProvider).withdrawCollateral()
      )
        .to.be.revertedWithCustomError(collateralManagement, "NotResigned")
        .withArgs(notProvider.address);
    });
    it("revert if the resign delay has not passed", async function () {
      const { collateralManagement, pegInLp, pegOutLp, fullLp } =
        await loadFixture(deployCollateralManagementWithProviders);
      const providers = [pegInLp, pegOutLp, fullLp];
      for (const provider of providers) {
        await expect(collateralManagement.connect(provider).resign()).not.to.be
          .reverted;
        const resignBlockNum = await collateralManagement.getResignationBlock(
          provider.address
        );
        await mine(COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS - 2n);
        await expect(
          collateralManagement.connect(provider).withdrawCollateral()
        )
          .to.be.revertedWithCustomError(
            collateralManagement,
            "ResignationDelayNotMet"
          )
          .withArgs(
            provider.address,
            resignBlockNum,
            COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS
          );
      }
    });
    it("revert if there is no collateral to withdraw", async function () {
      const { collateralManagement, providers, slasher } = await loadFixture(
        deployCollateralManagementWithProviders
      );
      for (const provider of providers) {
        await expect(collateralManagement.connect(provider.signer).resign()).not
          .to.be.reverted;
        if (provider.pegIn) {
          const amount = ethers.parseEther("300");
          const quote = getEmptyPegInQuote();
          quote.penaltyFee = amount;
          quote.liquidityProviderRskAddress = provider.signer.address;
          await expect(
            collateralManagement
              .connect(slasher)
              .slashPegInCollateral(ZERO_ADDRESS, quote, zeroPadBytes("0x", 32))
          ).not.to.be.reverted;
        }
        if (provider.pegOut) {
          const amount = ethers.parseEther("300");
          const quote = getEmptyPegOutQuote();
          quote.penaltyFee = amount;
          quote.lpRskAddress = provider.signer.address;
          await expect(
            collateralManagement
              .connect(slasher)
              .slashPegOutCollateral(
                ZERO_ADDRESS,
                quote,
                zeroPadBytes("0x", 32)
              )
          ).not.to.be.reverted;
        }
        await mine(COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS);
        await expect(
          collateralManagement.connect(provider.signer).withdrawCollateral()
        )
          .to.be.revertedWithCustomError(
            collateralManagement,
            "NothingToWithdraw"
          )
          .withArgs(provider.signer.address);
      }
    });
    it("allow providers to withdraw collateral", async function () {
      const { collateralManagement, providers, slasher } = await loadFixture(
        deployCollateralManagementWithProviders
      );
      for (const provider of providers) {
        const pegInCollateral = await collateralManagement.getPegInCollateral(
          provider.signer.address
        );
        const pegOutCollateral = await collateralManagement.getPegOutCollateral(
          provider.signer.address
        );
        if (provider.pegIn) {
          const quote = getEmptyPegInQuote();
          quote.penaltyFee = pegInCollateral / 2n;
          quote.liquidityProviderRskAddress = provider.signer.address;
          await expect(
            collateralManagement
              .connect(slasher)
              .slashPegInCollateral(ZERO_ADDRESS, quote, zeroPadBytes("0x", 32))
          ).not.to.be.reverted;
        }
        if (provider.pegOut) {
          const quote = getEmptyPegOutQuote();
          quote.penaltyFee = pegOutCollateral / 2n;
          quote.lpRskAddress = provider.signer.address;
          await expect(
            collateralManagement
              .connect(slasher)
              .slashPegOutCollateral(
                ZERO_ADDRESS,
                quote,
                zeroPadBytes("0x", 32)
              )
          ).not.to.be.reverted;
        }
        await expect(collateralManagement.connect(provider.signer).resign()).not
          .to.be.reverted;
        await mine(COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS);
        const tx = await collateralManagement
          .connect(provider.signer)
          .withdrawCollateral();
        const totalWithdrawal = pegInCollateral / 2n + pegOutCollateral / 2n;
        await expect(tx)
          .to.emit(collateralManagement, "WithdrawCollateral")
          .withArgs(provider.signer.address, totalWithdrawal);
        await expect(tx).to.changeEtherBalances(
          [provider.signer.address, await collateralManagement.getAddress()],
          [totalWithdrawal, -totalWithdrawal]
        );
        await expect(
          collateralManagement.getPegInCollateral(provider.signer.address)
        ).to.eventually.eq(0n);
        await expect(
          collateralManagement.getPegOutCollateral(provider.signer.address)
        ).to.eventually.eq(0n);
        await expect(
          collateralManagement.getResignationBlock(provider.signer.address)
        ).to.eventually.eq(0n);
      }
    });
    it("revert if the withdrawal fails", async function () {
      const { collateralManagement, adder } = await loadFixture(
        deployCollateralManagementWithRoles
      );
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
          .connect(adder)
          .addPegInCollateralTo(walletMockAddress, {
            value: ethers.parseEther("100"),
          })
      ).not.to.be.reverted;
      await expect(
        collateralManagement
          .connect(adder)
          .addPegOutCollateralTo(walletMockAddress, {
            value: ethers.parseEther("100"),
          })
      ).not.to.be.reverted;
      await expect(
        walletMock.execute(
          collateralManagementAddress,
          0n,
          collateralManagement.interface.encodeFunctionData("resign")
        )
      ).not.to.be.reverted;
      await mine(COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS);
      await walletMock.setRejectFunds(true);
      const error = collateralManagement.interface.encodeErrorResult(
        "WithdrawalFailed",
        [walletMockAddress, ethers.parseEther("200")]
      );
      await expect(
        walletMock.execute(
          collateralManagementAddress,
          0n,
          collateralManagement.interface.encodeFunctionData(
            "withdrawCollateral"
          )
        )
      )
        .to.emit(walletMock, "TransactionRejected")
        .withArgs(collateralManagementAddress, 0n, error);
    });
  });

  describe("isRegistered function should", function () {
    it("return true if the provider has collateral and hasn't resigned", async function () {
      const { collateralManagement, pegInLp, pegOutLp, fullLp } =
        await loadFixture(deployCollateralManagementWithProviders);

      await expect(
        collateralManagement.isRegistered(ProviderType.PegIn, pegInLp.address)
      ).to.eventually.be.true;
      await expect(
        collateralManagement.isRegistered(ProviderType.PegOut, pegInLp.address)
      ).to.eventually.be.false;
      await expect(
        collateralManagement.isRegistered(ProviderType.Both, pegInLp.address)
      ).to.eventually.be.false;

      await expect(
        collateralManagement.isRegistered(ProviderType.PegOut, pegOutLp.address)
      ).to.eventually.be.true;
      await expect(
        collateralManagement.isRegistered(ProviderType.PegIn, pegOutLp.address)
      ).to.eventually.be.false;
      await expect(
        collateralManagement.isRegistered(ProviderType.Both, pegOutLp.address)
      ).to.eventually.be.false;

      await expect(
        collateralManagement.isRegistered(ProviderType.PegIn, fullLp.address)
      ).to.eventually.be.true;
      await expect(
        collateralManagement.isRegistered(ProviderType.PegOut, fullLp.address)
      ).to.eventually.be.true;
      await expect(
        collateralManagement.isRegistered(ProviderType.Both, fullLp.address)
      ).to.eventually.be.true;
    });

    it("return false if the provider has resigned", async function () {
      const { collateralManagement, pegInLp, pegOutLp, fullLp } =
        await loadFixture(deployCollateralManagementWithProviders);

      await expect(collateralManagement.connect(pegInLp).resign()).not.to.be
        .reverted;
      await expect(collateralManagement.connect(pegOutLp).resign()).not.to.be
        .reverted;
      await expect(collateralManagement.connect(fullLp).resign()).not.to.be
        .reverted;

      await expect(
        collateralManagement.isRegistered(ProviderType.PegIn, pegInLp.address)
      ).to.eventually.be.false;
      await expect(
        collateralManagement.isRegistered(ProviderType.PegOut, pegInLp.address)
      ).to.eventually.be.false;
      await expect(
        collateralManagement.isRegistered(ProviderType.Both, pegInLp.address)
      ).to.eventually.be.false;

      await expect(
        collateralManagement.isRegistered(ProviderType.PegOut, pegOutLp.address)
      ).to.eventually.be.false;
      await expect(
        collateralManagement.isRegistered(ProviderType.PegIn, pegOutLp.address)
      ).to.eventually.be.false;
      await expect(
        collateralManagement.isRegistered(ProviderType.Both, pegOutLp.address)
      ).to.eventually.be.false;

      await expect(
        collateralManagement.isRegistered(ProviderType.PegIn, fullLp.address)
      ).to.eventually.be.false;
      await expect(
        collateralManagement.isRegistered(ProviderType.PegOut, fullLp.address)
      ).to.eventually.be.false;
      await expect(
        collateralManagement.isRegistered(ProviderType.Both, fullLp.address)
      ).to.eventually.be.false;
    });
  });

  describe("isCollateralSufficient function should", function () {
    it("return true if the provider has at least the minimum collateral and hasn't resigned", async function () {
      const { collateralManagement, pegInLp, pegOutLp, fullLp } =
        await loadFixture(deployCollateralManagementWithProviders);

      await expect(
        collateralManagement.isCollateralSufficient(
          ProviderType.PegIn,
          pegInLp.address
        )
      ).to.eventually.be.true;
      await expect(
        collateralManagement.isCollateralSufficient(
          ProviderType.PegOut,
          pegInLp.address
        )
      ).to.eventually.be.false;
      await expect(
        collateralManagement.isCollateralSufficient(
          ProviderType.Both,
          pegInLp.address
        )
      ).to.eventually.be.false;

      await expect(
        collateralManagement.isCollateralSufficient(
          ProviderType.PegOut,
          pegOutLp.address
        )
      ).to.eventually.be.true;
      await expect(
        collateralManagement.isCollateralSufficient(
          ProviderType.PegIn,
          pegOutLp.address
        )
      ).to.eventually.be.false;
      await expect(
        collateralManagement.isCollateralSufficient(
          ProviderType.Both,
          pegOutLp.address
        )
      ).to.eventually.be.false;

      await expect(
        collateralManagement.isCollateralSufficient(
          ProviderType.PegIn,
          fullLp.address
        )
      ).to.eventually.be.true;
      await expect(
        collateralManagement.isCollateralSufficient(
          ProviderType.PegOut,
          fullLp.address
        )
      ).to.eventually.be.true;
      await expect(
        collateralManagement.isCollateralSufficient(
          ProviderType.Both,
          fullLp.address
        )
      ).to.eventually.be.true;
    });

    it("return false if the provider has resigned", async function () {
      const { collateralManagement, providers } = await loadFixture(
        deployCollateralManagementWithProviders
      );

      for (const provider of providers) {
        await expect(collateralManagement.connect(provider.signer).resign()).not
          .to.be.reverted;
        await expect(
          collateralManagement.isCollateralSufficient(
            ProviderType.PegIn,
            provider.signer.address
          )
        ).to.eventually.be.false;
        await expect(
          collateralManagement.isCollateralSufficient(
            ProviderType.PegOut,
            provider.signer.address
          )
        ).to.eventually.be.false;
        await expect(
          collateralManagement.isCollateralSufficient(
            ProviderType.Both,
            provider.signer.address
          )
        ).to.eventually.be.false;
      }
    });

    it("return false if the provider has less than the minimum collateral", async function () {
      const { collateralManagement, slasher, providers } = await loadFixture(
        deployCollateralManagementWithProviders
      );

      for (const provider of providers) {
        const emptyPegInCollateral = getEmptyPegInQuote();
        const emptyPegOutCollateral = getEmptyPegOutQuote();
        emptyPegInCollateral.penaltyFee = ethers.parseEther("1000000");
        emptyPegOutCollateral.penaltyFee = ethers.parseEther("1000000");
        emptyPegInCollateral.liquidityProviderRskAddress =
          provider.signer.address;
        emptyPegOutCollateral.lpRskAddress = provider.signer.address;

        await expect(
          collateralManagement
            .connect(slasher)
            .slashPegInCollateral(
              ZERO_ADDRESS,
              emptyPegInCollateral,
              zeroPadBytes("0x", 32)
            )
        ).not.to.be.reverted;
        await expect(
          collateralManagement
            .connect(slasher)
            .slashPegOutCollateral(
              ZERO_ADDRESS,
              emptyPegOutCollateral,
              zeroPadBytes("0x", 32)
            )
        ).not.to.be.reverted;
        await expect(
          collateralManagement.isCollateralSufficient(
            ProviderType.PegIn,
            provider.signer.address
          )
        ).to.eventually.be.false;
        await expect(
          collateralManagement.isCollateralSufficient(
            ProviderType.PegOut,
            provider.signer.address
          )
        ).to.eventually.be.false;
        await expect(
          collateralManagement.isCollateralSufficient(
            ProviderType.Both,
            provider.signer.address
          )
        ).to.eventually.be.false;
      }
    });
  });
});
