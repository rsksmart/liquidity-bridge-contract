import {
  loadFixture,
  mine,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  deployDiscoveryFixture,
  deployDiscoveryWithProvidersFixture,
} from "../test/discovery/fixtures";
import { ProviderType, COLLATERAL_CONSTANTS } from "../test/utils/constants";

describe("FlyoverDiscovery Integration Tests", () => {
  describe("Cross-contract: Collateral allocation during registration", () => {
    it("should correctly allocate collateral for ProviderType.PegIn", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-1)!;

      const collateralAmount = MIN_COLLATERAL;
      await discovery
        .connect(lp)
        .register(
          "PegIn LP",
          "http://localhost/api",
          true,
          ProviderType.PegIn,
          {
            value: collateralAmount,
          }
        );

      // Verify collateral allocation in CollateralManagement contract
      expect(
        await collateralManagement.getPegInCollateral(lp.address)
      ).to.equal(collateralAmount);
      expect(
        await collateralManagement.getPegOutCollateral(lp.address)
      ).to.equal(0n);
    });

    it("should correctly allocate collateral for ProviderType.PegOut", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-2)!;

      const collateralAmount = MIN_COLLATERAL;
      await discovery
        .connect(lp)
        .register(
          "PegOut LP",
          "http://localhost/api",
          true,
          ProviderType.PegOut,
          {
            value: collateralAmount,
          }
        );

      // Verify collateral allocation in CollateralManagement contract
      expect(
        await collateralManagement.getPegInCollateral(lp.address)
      ).to.equal(0n);
      expect(
        await collateralManagement.getPegOutCollateral(lp.address)
      ).to.equal(collateralAmount);
    });

    it("should correctly allocate collateral for ProviderType.Both with even amount", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-3)!;

      const evenAmount = MIN_COLLATERAL * 2n;
      await discovery
        .connect(lp)
        .register("Both LP", "http://localhost/api", true, ProviderType.Both, {
          value: evenAmount,
        });

      // Verify exact 50/50 split in CollateralManagement
      const expectedHalf = evenAmount / 2n;
      expect(
        await collateralManagement.getPegInCollateral(lp.address)
      ).to.equal(expectedHalf);
      expect(
        await collateralManagement.getPegOutCollateral(lp.address)
      ).to.equal(expectedHalf);
    });

    it("should correctly allocate collateral for ProviderType.Both with odd amount", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-4)!;

      const oddAmount = MIN_COLLATERAL * 2n + 1n;
      await discovery
        .connect(lp)
        .register(
          "Both LP Odd",
          "http://localhost/api",
          true,
          ProviderType.Both,
          {
            value: oddAmount,
          }
        );

      // Verify PegIn gets the remainder in CollateralManagement
      const halfAmount = oddAmount / 2n;
      const remainder = oddAmount % 2n;
      const expectedPegIn = halfAmount + remainder;
      const expectedPegOut = halfAmount;

      expect(
        await collateralManagement.getPegInCollateral(lp.address)
      ).to.equal(expectedPegIn);
      expect(
        await collateralManagement.getPegOutCollateral(lp.address)
      ).to.equal(expectedPegOut);

      // Verify total allocation equals the original amount
      const totalAllocated =
        (await collateralManagement.getPegInCollateral(lp.address)) +
        (await collateralManagement.getPegOutCollateral(lp.address));
      expect(totalAllocated).to.equal(oddAmount);
    });

    it("should verify collateral is actually transferred to CollateralManagement contract", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-5)!;

      // Get initial balance of CollateralManagement contract
      const initialBalance = await ethers.provider.getBalance(
        await collateralManagement.getAddress()
      );

      const collateralAmount = MIN_COLLATERAL;
      await discovery
        .connect(lp)
        .register("Test LP", "http://localhost/api", true, ProviderType.PegIn, {
          value: collateralAmount,
        });

      // Verify the CollateralManagement contract received the funds
      const finalBalance = await ethers.provider.getBalance(
        await collateralManagement.getAddress()
      );
      expect(finalBalance - initialBalance).to.equal(collateralAmount);
    });

    it("should emit correct events in both contracts during registration", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-6)!;

      const collateralAmount = MIN_COLLATERAL;
      const tx = await discovery
        .connect(lp)
        .register(
          "Event LP",
          "http://localhost/api",
          true,
          ProviderType.PegIn,
          {
            value: collateralAmount,
          }
        );

      // Verify the Register event in Discovery
      await expect(tx)
        .to.emit(discovery, "Register")
        .withArgs(1n, lp.address, collateralAmount);

      // Verify the PegInCollateralAdded event in CollateralManagement
      await expect(tx)
        .to.emit(collateralManagement, "PegInCollateralAdded")
        .withArgs(lp.address, collateralAmount);
    });
  });

  describe("Cross-contract: isOperational checks", () => {
    it("should return true only for providers with sufficient collateral for their type", async () => {
      const { discovery, pegInLp, fullLp, pegOutLp } = await loadFixture(
        deployDiscoveryWithProvidersFixture
      );

      // Test PegIn operations (Discovery queries CollateralManagement)
      expect(
        await discovery.isOperational(ProviderType.PegIn, pegInLp.address)
      ).to.equal(true);
      expect(
        await discovery.isOperational(ProviderType.PegIn, fullLp.address)
      ).to.equal(true);
      expect(
        await discovery.isOperational(ProviderType.PegIn, pegOutLp.address)
      ).to.equal(false);

      // Test PegOut operations
      expect(
        await discovery.isOperational(ProviderType.PegOut, pegInLp.address)
      ).to.equal(false);
      expect(
        await discovery.isOperational(ProviderType.PegOut, fullLp.address)
      ).to.equal(true);
      expect(
        await discovery.isOperational(ProviderType.PegOut, pegOutLp.address)
      ).to.equal(true);

      // Test Both operations (requires sufficient collateral for both PegIn AND PegOut)
      expect(
        await discovery.isOperational(ProviderType.Both, pegInLp.address)
      ).to.equal(false); // Only has PegIn collateral
      expect(
        await discovery.isOperational(ProviderType.Both, pegOutLp.address)
      ).to.equal(false); // Only has PegOut collateral
      expect(
        await discovery.isOperational(ProviderType.Both, fullLp.address)
      ).to.equal(true); // Has both PegIn and PegOut collateral
    });

    it("should reflect collateral slashing in operational status", async () => {
      const {
        discovery,
        collateralManagement,
        signers,
        MIN_COLLATERAL,
        owner,
      } = await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-1)!;

      // Register with enough collateral
      await discovery
        .connect(lp)
        .register("LP", "url", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL * 2n,
        });

      // Initially operational
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(true);

      // Slash some collateral (but still above minimum)
      await collateralManagement
        .connect(owner)
        .grantRole(
          await collateralManagement.COLLATERAL_SLASHER(),
          owner.address
        );
      const { getEmptyPegInQuote } = await import("../test/utils/quotes");
      const quote1 = getEmptyPegInQuote();
      quote1.liquidityProviderRskAddress = lp.address;
      quote1.penaltyFee = MIN_COLLATERAL / 2n;
      await collateralManagement
        .connect(owner)
        .slashPegInCollateral(ethers.ZeroAddress, quote1, ethers.ZeroHash);

      // Still operational
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(true);

      // Slash more to go below minimum
      const quote2 = getEmptyPegInQuote();
      quote2.liquidityProviderRskAddress = lp.address;
      quote2.penaltyFee = MIN_COLLATERAL;
      await collateralManagement
        .connect(owner)
        .slashPegInCollateral(ethers.ZeroAddress, quote2, ethers.ZeroHash);

      // No longer operational
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(false);
    });

    it("should reflect collateral additions in operational status", async () => {
      const {
        discovery,
        collateralManagement,
        signers,
        MIN_COLLATERAL,
        owner,
      } = await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-1)!;

      // Register with minimum collateral
      await discovery
        .connect(lp)
        .register("LP", "url", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });

      // Slash below minimum
      await collateralManagement
        .connect(owner)
        .grantRole(
          await collateralManagement.COLLATERAL_SLASHER(),
          owner.address
        );
      const { getEmptyPegInQuote } = await import("../test/utils/quotes");
      const quote = getEmptyPegInQuote();
      quote.liquidityProviderRskAddress = lp.address;
      quote.penaltyFee = MIN_COLLATERAL;
      await collateralManagement
        .connect(owner)
        .slashPegInCollateral(ethers.ZeroAddress, quote, ethers.ZeroHash);

      // Not operational
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(false);

      // Add collateral back
      await collateralManagement
        .connect(lp)
        .addPegInCollateral({ value: MIN_COLLATERAL });

      // Operational again
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(true);
    });
  });

  describe("Cross-contract: Resignation flow", () => {
    it("should hide resigned provider from Discovery listing", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const [lp1, lp2, lp3] = signers.slice(-3);

      // Register multiple providers
      await discovery
        .connect(lp1)
        .register("LP1", "url1", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });
      await discovery
        .connect(lp2)
        .register("LP2", "url2", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });
      await discovery
        .connect(lp3)
        .register("LP3", "url3", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });

      // Verify all listed
      let providers = await discovery.getProviders();
      expect(providers.length).to.equal(3);

      // Resign one provider in CollateralManagement
      const resignTx = await collateralManagement.connect(lp2).resign();
      await expect(resignTx)
        .to.emit(collateralManagement, "Resigned")
        .withArgs(lp2.address);

      // Verify disappeared from Discovery listing
      providers = await discovery.getProviders();
      expect(providers.length).to.equal(2);
      expect(providers.map((p) => p.id)).to.deep.equal([1n, 3n]);

      // Verify getProvider still works
      const provider = await discovery.getProvider(lp2.address);
      expect(provider.id).to.equal(2n);

      // Verify isOperational returns false
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp2.address)
      ).to.equal(false);
    });

    it("should complete full resignation and withdrawal lifecycle affecting Discovery", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-1)!;

      // Register provider (appears in Discovery)
      await discovery
        .connect(lp)
        .register("LP", "url", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL * 2n,
        });
      expect((await discovery.getProviders()).length).to.equal(1);
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(true);

      // Resign in CollateralManagement (disappears from Discovery list)
      await collateralManagement.connect(lp).resign();
      expect((await discovery.getProviders()).length).to.equal(0);
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(false);

      // Wait resignation delay and withdraw
      await mine(COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS);
      await collateralManagement.connect(lp).withdrawCollateral();

      // Verify complete cleanup in CollateralManagement
      expect(
        await collateralManagement.getPegInCollateral(lp.address)
      ).to.equal(0n);
      expect(
        await collateralManagement.getResignationBlock(lp.address)
      ).to.equal(0n);

      // Discovery still knows the provider existed (but not operational)
      const provider = await discovery.getProvider(lp.address);
      expect(provider.id).to.equal(1n);
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(false);
    });

    it("should support re-registration after full resignation and withdrawal", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-1)!;

      // Register as PegIn provider
      await discovery
        .connect(lp)
        .register("LP PegIn", "url1", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });

      let provider = await discovery.getProvider(lp.address);
      expect(provider.providerType).to.equal(ProviderType.PegIn);
      expect(provider.id).to.equal(1n);

      // Resign and withdraw
      await collateralManagement.connect(lp).resign();
      await mine(COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS);
      await collateralManagement.connect(lp).withdrawCollateral();

      // Re-register as PegOut provider
      await discovery
        .connect(lp)
        .register("LP PegOut", "url2", true, ProviderType.PegOut, {
          value: MIN_COLLATERAL,
        });

      // Verify new provider type in Discovery
      provider = await discovery.getProvider(lp.address);
      expect(provider.providerType).to.equal(ProviderType.PegOut);
      expect(provider.id).to.equal(2n); // New ID assigned
      expect(provider.name).to.equal("LP PegOut");

      // Verify new collateral allocation in CollateralManagement
      expect(
        await collateralManagement.getPegInCollateral(lp.address)
      ).to.equal(0n);
      expect(
        await collateralManagement.getPegOutCollateral(lp.address)
      ).to.equal(MIN_COLLATERAL);

      // Verify operational for new type
      expect(
        await discovery.isOperational(ProviderType.PegOut, lp.address)
      ).to.equal(true);
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(false);
    });
  });

  describe("Complex multi-provider scenario (legacy test lines 186-271)", () => {
    it("should list only enabled and non-resigned providers in complex scenario", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);

      // Create 8 providers with various states
      const [lp1, lp2, lp3, lp4, lp5, lp6, lp7, lp8] = signers.slice(-8);

      /**
       * Target provider statuses:
       * LP1 - active (enabled + not resigned)
       * LP2 - disabled but not resigned
       * LP3 - active (enabled + not resigned)
       * LP4 - resigned and disabled
       * LP5 - resigned but still enabled
       * LP6 - disabled but not resigned
       * LP7 - active (enabled + not resigned)
       * LP8 - resigned but enabled
       */

      // Register all 8 providers as enabled
      await discovery
        .connect(lp1)
        .register("LP1", "url1", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });
      await discovery
        .connect(lp2)
        .register("LP2", "url2", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });
      await discovery
        .connect(lp3)
        .register("LP3", "url3", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });
      await discovery
        .connect(lp4)
        .register("LP4", "url4", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });
      await discovery
        .connect(lp5)
        .register("LP5", "url5", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });
      await discovery
        .connect(lp6)
        .register("LP6", "url6", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });
      await discovery
        .connect(lp7)
        .register("LP7", "url7", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });
      await discovery
        .connect(lp8)
        .register("LP8", "url8", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });

      // All 8 should be listed initially
      let providers = await discovery.getProviders();
      expect(providers.length).to.equal(8);

      // LP2 - disable (not resigned)
      await discovery.connect(lp2).setProviderStatus(2, false);

      // LP3 - keep active (no changes)

      // LP4 - resign and disable
      await discovery.connect(lp4).setProviderStatus(4, false);
      await collateralManagement.connect(lp4).resign();

      // LP5 - resign but keep enabled
      await collateralManagement.connect(lp5).resign();

      // LP6 - disable (not resigned)
      await discovery.connect(lp6).setProviderStatus(6, false);

      // LP7 - keep active (no changes)

      // LP8 - resign but keep enabled
      await collateralManagement.connect(lp8).resign();

      // Get final provider list
      providers = await discovery.getProviders();

      // Should only list: LP1, LP3, LP7 (enabled + not resigned)
      expect(providers.length).to.equal(3);
      expect(providers.map((p) => p.id)).to.deep.equal([1n, 3n, 7n]);

      // Verify expected providers are in the list
      expect(providers[0].providerAddress).to.equal(lp1.address);
      expect(providers[0].name).to.equal("LP1");
      expect(providers[0].status).to.equal(true);

      expect(providers[1].providerAddress).to.equal(lp3.address);
      expect(providers[1].name).to.equal("LP3");
      expect(providers[1].status).to.equal(true);

      expect(providers[2].providerAddress).to.equal(lp7.address);
      expect(providers[2].name).to.equal("LP7");
      expect(providers[2].status).to.equal(true);

      // Verify LP2, LP4, LP5, LP6, LP8 are NOT in the list
      const listedIds = providers.map((p) => p.id);
      expect(listedIds).to.not.include(2n); // LP2 - disabled
      expect(listedIds).to.not.include(4n); // LP4 - resigned and disabled
      expect(listedIds).to.not.include(5n); // LP5 - resigned
      expect(listedIds).to.not.include(6n); // LP6 - disabled
      expect(listedIds).to.not.include(8n); // LP8 - resigned

      // But all providers still exist and can be queried
      await expect(discovery.getProvider(lp2.address)).to.not.be.reverted;
      await expect(discovery.getProvider(lp4.address)).to.not.be.reverted;
      await expect(discovery.getProvider(lp5.address)).to.not.be.reverted;
      await expect(discovery.getProvider(lp6.address)).to.not.be.reverted;
      await expect(discovery.getProvider(lp8.address)).to.not.be.reverted;
    });
  });
});
