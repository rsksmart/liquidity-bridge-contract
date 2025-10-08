import {
  loadFixture,
  mine,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { deployDiscoveryFixture } from "../test/discovery/fixtures";
import { ProviderType, COLLATERAL_CONSTANTS } from "../test/utils/constants";

describe("CollateralManagement Integration Tests", () => {
  describe("Cross-contract: Adding collateral affects Discovery", () => {
    it("should make provider operational in Discovery after adding sufficient collateral", async () => {
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

      // Slash to below minimum
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

      // Verify not operational in Discovery
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(false);

      // Add collateral in CollateralManagement
      await collateralManagement
        .connect(lp)
        .addPegInCollateral({ value: MIN_COLLATERAL });

      // Verify operational again in Discovery
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(true);
      expect(
        await collateralManagement.getPegInCollateral(lp.address)
      ).to.equal(MIN_COLLATERAL);
    });
  });

  describe("Cross-contract: Slashing affects Discovery", () => {
    it("should make provider non-operational in Discovery after slashing below minimum", async () => {
      const {
        discovery,
        collateralManagement,
        signers,
        MIN_COLLATERAL,
        owner,
      } = await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-1)!;

      // Register with 2x minimum collateral
      await discovery
        .connect(lp)
        .register("LP", "url", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL * 2n,
        });

      // Verify operational
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(true);

      // Slash in CollateralManagement to below minimum
      await collateralManagement
        .connect(owner)
        .grantRole(
          await collateralManagement.COLLATERAL_SLASHER(),
          owner.address
        );
      const { getEmptyPegInQuote } = await import("../test/utils/quotes");
      const quote = getEmptyPegInQuote();
      quote.liquidityProviderRskAddress = lp.address;
      quote.penaltyFee = MIN_COLLATERAL * 2n;

      await collateralManagement
        .connect(owner)
        .slashPegInCollateral(ethers.ZeroAddress, quote, ethers.ZeroHash);

      // Verify not operational in Discovery
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(false);

      // Provider should also disappear from Discovery listing
      const providers = await discovery.getProviders();
      expect(providers.length).to.equal(0);
    });

    it("should keep provider in Discovery listing if still above minimum after slashing", async () => {
      const {
        discovery,
        collateralManagement,
        signers,
        MIN_COLLATERAL,
        owner,
      } = await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-1)!;

      // Register with 3x minimum collateral
      await discovery
        .connect(lp)
        .register("LP", "url", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL * 3n,
        });

      // Slash but keep above minimum
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

      // Still operational in Discovery
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(true);

      // Still in Discovery listing
      const providers = await discovery.getProviders();
      expect(providers.length).to.equal(1);
      expect(providers[0].providerAddress).to.equal(lp.address);
    });
  });

  describe("Cross-contract: Resignation affects Discovery", () => {
    it("should immediately hide provider from Discovery listing upon resignation", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const [lp1, lp2] = signers.slice(-2);

      // Register two providers
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

      // Both listed in Discovery
      let providers = await discovery.getProviders();
      expect(providers.length).to.equal(2);

      // Resign LP1 in CollateralManagement
      await collateralManagement.connect(lp1).resign();

      // LP1 should disappear from Discovery listing immediately
      providers = await discovery.getProviders();
      expect(providers.length).to.equal(1);
      expect(providers[0].providerAddress).to.equal(lp2.address);

      // But LP1 can still be queried in Discovery
      const lp1Provider = await discovery.getProvider(lp1.address);
      expect(lp1Provider.id).to.equal(1n);

      // LP1 is not operational in Discovery
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp1.address)
      ).to.equal(false);
    });

    it("should keep provider hidden in Discovery even after withdrawal", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-1)!;

      // Register provider
      await discovery
        .connect(lp)
        .register("LP", "url", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });

      // Verify listed
      let providers = await discovery.getProviders();
      expect(providers.length).to.equal(1);

      // Resign in CollateralManagement
      await collateralManagement.connect(lp).resign();

      // Hidden from Discovery listing
      providers = await discovery.getProviders();
      expect(providers.length).to.equal(0);

      // Withdraw collateral
      await mine(COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS);
      await collateralManagement.connect(lp).withdrawCollateral();

      // Still hidden from Discovery listing
      providers = await discovery.getProviders();
      expect(providers.length).to.equal(0);

      // Still not operational
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(false);

      // But can still be queried
      const provider = await discovery.getProvider(lp.address);
      expect(provider.id).to.equal(1n);
    });

    it("should allow provider to appear in Discovery again after re-registration", async () => {
      const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
        await loadFixture(deployDiscoveryFixture);
      const lp = signers.at(-1)!;

      // Initial registration
      await discovery
        .connect(lp)
        .register("LP First", "url1", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        });

      let providers = await discovery.getProviders();
      expect(providers.length).to.equal(1);
      expect(providers[0].id).to.equal(1n);

      // Resign and withdraw
      await collateralManagement.connect(lp).resign();
      await mine(COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS);
      await collateralManagement.connect(lp).withdrawCollateral();

      // Hidden from listing
      providers = await discovery.getProviders();
      expect(providers.length).to.equal(0);

      // Re-register
      await discovery
        .connect(lp)
        .register("LP Second", "url2", true, ProviderType.PegOut, {
          value: MIN_COLLATERAL,
        });

      // Appears in listing again with new ID
      providers = await discovery.getProviders();
      expect(providers.length).to.equal(1);
      expect(providers[0].id).to.equal(2n);
      expect(providers[0].name).to.equal("LP Second");
      expect(providers[0].providerType).to.equal(ProviderType.PegOut);

      // Operational for new type
      expect(
        await discovery.isOperational(ProviderType.PegOut, lp.address)
      ).to.equal(true);
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp.address)
      ).to.equal(false);
    });
  });

  describe("Cross-contract: Complex collateral scenarios", () => {
    it("should handle multiple providers with varying collateral levels affecting Discovery", async () => {
      const {
        discovery,
        collateralManagement,
        signers,
        MIN_COLLATERAL,
        owner,
      } = await loadFixture(deployDiscoveryFixture);
      const [lp1, lp2, lp3, lp4] = signers.slice(-4);

      // Register 4 providers with different collateral amounts
      await discovery
        .connect(lp1)
        .register("LP1", "url1", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL, // Exactly minimum
        });
      await discovery
        .connect(lp2)
        .register("LP2", "url2", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL * 2n, // 2x minimum
        });
      await discovery
        .connect(lp3)
        .register("LP3", "url3", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL * 5n, // 5x minimum
        });
      await discovery
        .connect(lp4)
        .register("LP4", "url4", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL * 10n, // 10x minimum
        });

      // All should be operational and listed
      let providers = await discovery.getProviders();
      expect(providers.length).to.equal(4);

      // Slash LP1 by small amount (goes below minimum)
      await collateralManagement
        .connect(owner)
        .grantRole(
          await collateralManagement.COLLATERAL_SLASHER(),
          owner.address
        );
      const { getEmptyPegInQuote } = await import("../test/utils/quotes");
      const quote1 = getEmptyPegInQuote();
      quote1.liquidityProviderRskAddress = lp1.address;
      quote1.penaltyFee = MIN_COLLATERAL / 10n;
      await collateralManagement
        .connect(owner)
        .slashPegInCollateral(ethers.ZeroAddress, quote1, ethers.ZeroHash);

      // LP1 should disappear from Discovery
      providers = await discovery.getProviders();
      expect(providers.length).to.equal(3);
      expect(providers.map((p) => p.providerAddress)).to.not.include(
        lp1.address
      );

      // Slash LP2 significantly but still above minimum
      const quote2 = getEmptyPegInQuote();
      quote2.liquidityProviderRskAddress = lp2.address;
      quote2.penaltyFee = MIN_COLLATERAL;
      await collateralManagement
        .connect(owner)
        .slashPegInCollateral(ethers.ZeroAddress, quote2, ethers.ZeroHash);

      // LP2 should still be listed
      providers = await discovery.getProviders();
      expect(providers.length).to.equal(3);
      expect(providers.map((p) => p.providerAddress)).to.include(lp2.address);

      // Resign LP3
      await collateralManagement.connect(lp3).resign();

      // LP3 should disappear
      providers = await discovery.getProviders();
      expect(providers.length).to.equal(2);
      expect(providers.map((p) => p.providerAddress)).to.not.include(
        lp3.address
      );

      // Only LP2 and LP4 should be listed
      expect(providers.map((p) => p.providerAddress)).to.deep.equal([
        lp2.address,
        lp4.address,
      ]);

      // Verify operational status
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp1.address)
      ).to.equal(false);
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp2.address)
      ).to.equal(true);
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp3.address)
      ).to.equal(false);
      expect(
        await discovery.isOperational(ProviderType.PegIn, lp4.address)
      ).to.equal(true);
    });
  });
});
