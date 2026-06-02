const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("VenturesSea Protocol", function () {
  let owner, governance, treasury, investor, builder;
  let ideaVault, builderHub, governanceVault, treasuryVault;
  let usdyToken;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    owner = signers[0];
    governance = signers[1];
    treasury = signers[2];
    investor = signers[3];
    builder = signers[4];

    const MockUSDY = await ethers.getContractFactory("MockMUSD");
    usdyToken = await MockUSDY.deploy();
    await usdyToken.waitForDeployment();

    const IdeaVault = await ethers.getContractFactory("IdeaVault");
    ideaVault = await IdeaVault.deploy();
    await ideaVault.waitForDeployment();
    await ideaVault.initialize(
      await usdyToken.getAddress(),
      await governance.getAddress(),
      await treasury.getAddress(),
      await owner.getAddress()
    );

    const BuilderHub = await ethers.getContractFactory("BuilderHub");
    builderHub = await BuilderHub.deploy();
    await builderHub.waitForDeployment();
    await builderHub.initialize(
      await governance.getAddress(),
      await treasury.getAddress(),
      await usdyToken.getAddress(),
      "0x0000000000000000000000000000000000000000",
      await owner.getAddress()
    );

    const GovernanceVault = await ethers.getContractFactory("GovernanceVault");
    governanceVault = await GovernanceVault.deploy();
    await governanceVault.waitForDeployment();
    await governanceVault.initialize(
      await ideaVault.getAddress(),
      await builderHub.getAddress(),
      await treasury.getAddress(),
      await owner.getAddress()
    );

    const TreasuryVault = await ethers.getContractFactory("TreasuryVault");
    treasuryVault = await TreasuryVault.deploy();
    await treasuryVault.waitForDeployment();
    await treasuryVault.initialize(
      "0x0000000000000000000000000000000000000000",
      await usdyToken.getAddress(),
      await governance.getAddress(),
      await ideaVault.getAddress(),
      await builderHub.getAddress(),
      await treasury.getAddress(),
      await owner.getAddress()
    );

    // Fund investor and treasury
    await usdyToken.mint(await investor.getAddress(), ethers.parseEther("100000"));
    await usdyToken.mint(await treasuryVault.getAddress(), ethers.parseEther("100000"));
  });

  describe("IdeaVault", function () {
    it("should create and fund idea", async function () {
      await ideaVault.createIdea("QmTest", ethers.parseEther("10000"), ethers.parseEther("50000"), 604800, 100, false);
      await ideaVault.openFunding(1, 604800);
      
      await usdyToken.connect(investor).approve(await ideaVault.getAddress(), ethers.parseEther("10000"));
      await ideaVault.connect(investor).fund(1, ethers.parseEther("1000"));
      
      const tokens = await ideaVault.getInvestorTokens(1, await investor.getAddress());
      expect(tokens).to.equal(100000n);
    });

    it("should select builder", async function () {
      await ideaVault.createIdea("QmTest", ethers.parseEther("1000"), ethers.parseEther("50000"), 604800, 100, false);
      await ideaVault.openFunding(1, 604800);
      await usdyToken.connect(investor).approve(await ideaVault.getAddress(), ethers.parseEther("10000"));
      await ideaVault.connect(investor).fund(1, ethers.parseEther("1000"));
      await ideaVault.closeFunding(1);
      
      await ideaVault.selectBuilder(1, await builder.getAddress(), 1500);
      
      const idea = await ideaVault.getIdea(1);
      expect(idea.selectedBuilder).to.equal(await builder.getAddress());
    });
  });

  describe("Full Protocol Flow", function () {
    it("should complete funding lifecycle", async function () {
      await builderHub.connect(builder).registerBuilder("QmBuilder");
      
      // 1. Create idea
      await ideaVault.createIdea("QmGreatIdea", ethers.parseEther("10000"), ethers.parseEther("50000"), 604800, 100, false);

      // 2. Open funding
      await ideaVault.openFunding(1, 604800);

      // 3. Fund
      await usdyToken.connect(investor).approve(await ideaVault.getAddress(), ethers.parseEther("50000"));
      await ideaVault.connect(investor).fund(1, ethers.parseEther("5000"));

      // 4. Close funding
      await ideaVault.closeFunding(1);
      expect(Number(await ideaVault.getIdeaState(1))).to.equal(2);

      // 5. Select builder
      await ideaVault.selectBuilder(1, await builder.getAddress(), 1500);
      expect(Number(await ideaVault.getIdeaState(1))).to.equal(3);

      // 6. Lock funding
      await ideaVault.lockFunding(1);
      expect(Number(await ideaVault.getIdeaState(1))).to.equal(4);

      // 7. Sign agreement and milestones
      const ipfsHash = ethers.keccak256(ethers.toUtf8Bytes("QmAgreementTerms"));
      await builderHub.proposeAgreement(1, await builder.getAddress(), ethers.parseEther("5000"), 1500, 12, ipfsHash);
      
      const signedHash = ethers.keccak256(ethers.toUtf8Bytes("QmSignedAgreement"));
      await builderHub.connect(builder).signAgreement(1, signedHash);
      
      await builderHub.connect(builder).submitMilestone(1, "QmM1", "Build", ethers.parseEther("2500"), 750);
      await builderHub.approveMilestone(1, 0);

      // 8. Submit final deliverable
      await builderHub.connect(builder).submitDeliverable(1, "QmFinalMVP");
      await builderHub.approveFinalDeliverable(1);

      // 9. Payout
      await treasuryVault.initiatePayout(1, await builder.getAddress(), ethers.parseEther("5000"), 1500);
      await treasuryVault.approvePayout(1);
      await treasuryVault.processPayout(1);

      // 10. Mark operational
      await ideaVault.markOperational(1);
      expect(Number(await ideaVault.getIdeaState(1))).to.equal(5);

      console.log("Full protocol flow completed successfully!");
    });
  });
});
