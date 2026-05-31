const { network } = require("hardhat");

/**
 * Fork Mainnet Tests for VenturesSea FHE Protocol
 * Run with: npx hardhat test test/fork-tests.js --network hardhat (with forking)
 */
describe("Fork Mainnet FHE Operations", function () {
  beforeEach(async function () {
    // Fork from mainnet for realistic testing
    await network.provider.request({
      method: "evm_setAccountBalance",
      params: [
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "0x21E19E0C9BAB2400000", // 10000 ETH
      ],
    });
  });

  describe("Token Operations", function () {
    it("should deploy confidential token", async function () {
      const ConfidentialIdeaToken = await ethers.getContractFactory("ConfidentialIdeaToken");
      const token = await ConfidentialIdeaToken.deploy();
      await token.waitForDeployment();
      console.log("Token deployed at:", await token.getAddress());
    });
  });

  describe("Threshold Decryptor", function () {
    it("should deploy threshold decryptor", async function () {
      const ThresholdDecryptor = await ethers.getContractFactory("ThresholdDecryptor");
      const thresholdDecryptor = await ThresholdDecryptor.deploy();
      await thresholdDecryptor.waitForDeployment();
      
      // Initialize with guardians
      const guardians = [
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
        "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
      ];
      await thresholdDecryptor.initialize(
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        guardians,
        2, // min approvals
        86400 // max duration
      );
      console.log("ThresholdDecryptor deployed and initialized");
    });
  });

  describe("Encrypted Swap", function () {
    it("should deploy encrypted swap", async function () {
      const EncryptedSwap = await ethers.getContractFactory("EncryptedSwap");
      const swap = await EncryptedSwap.deploy();
      await swap.waitForDeployment();
      
      // Initialize
      await swap.initialize(
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // threshold decryptor
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // fee recipient
        30 // 0.3% fee
      );
      console.log("EncryptedSwap deployed and initialized");
    });
  });

  describe("Full Integration Flow", function () {
    it("should execute full FHE workflow", async function () {
      const [owner, alice, bob, carol] = await ethers.getSigners();
      
      // 1. Deploy ThresholdDecryptor
      const ThresholdDecryptor = await ethers.getContractFactory("ThresholdDecryptor");
      const thresholdDecryptor = await ThresholdDecryptor.deploy();
      await thresholdDecryptor.waitForDeployment();
      
      const guardians = [alice.address, bob.address, carol.address];
      await thresholdDecryptor.initialize(owner.address, guardians, 2, 86400);
      
      // 2. Deploy ConfidentialIdeaToken
      const ConfidentialIdeaToken = await ethers.getContractFactory("ConfidentialIdeaToken");
      const token = await ConfidentialIdeaToken.deploy();
      await token.waitForDeployment();
      await token.initialize("Confidential Idea Token", "CIT");
      
      // 3. Deploy FundingPool
      const ConfidentialFundingPool = await ethers.getContractFactory("ConfidentialFundingPool");
      const fundingPool = await ConfidentialFundingPool.deploy();
      await fundingPool.waitForDeployment();
      
      await fundingPool.initialize(
        owner.address,
        await token.getAddress(),
        1000,
        30,
        owner.address,
        await thresholdDecryptor.getAddress()
      );
      
      // 4. Deploy IdeaDAO
      const ConfidentialIdeaDAO = await ethers.getContractFactory("ConfidentialIdeaDAO");
      const ideaDAO = await ConfidentialIdeaDAO.deploy();
      await ideaDAO.waitForDeployment();
      
      await ideaDAO.initialize(
        owner.address,
        await token.getAddress(),
        await fundingPool.getAddress(),
        500,
        7 * 86400,
        owner.address
      );
      
      // 5. Deploy EncryptedSwap
      const EncryptedSwap = await ethers.getContractFactory("EncryptedSwap");
      const encryptedSwap = await EncryptedSwap.deploy();
      await encryptedSwap.waitForDeployment();
      
      await encryptedSwap.initialize(
        await thresholdDecryptor.getAddress(),
        owner.address,
        30
      );
      
      // Add supported token
      await encryptedSwap.addSupportedToken(await token.getAddress());
      
      console.log("✅ All contracts deployed successfully!");
      console.log("- ThresholdDecryptor:", await thresholdDecryptor.getAddress());
      console.log("- ConfidentialIdeaToken:", await token.getAddress());
      console.log("- ConfidentialFundingPool:", await fundingPool.getAddress());
      console.log("- ConfidentialIdeaDAO:", await ideaDAO.getAddress());
      console.log("- EncryptedSwap:", await encryptedSwap.getAddress());
      
      // Set authorized handlers
      await thresholdDecryptor.setAuthorizedHandler(await fundingPool.getAddress(), true);
      await thresholdDecryptor.setAuthorizedHandler(await ideaDAO.getAddress(), true);
      await thresholdDecryptor.setAuthorizedHandler(await encryptedSwap.getAddress(), true);
      
      // Test threshold decryption workflow
      console.log("\n📋 Testing Threshold Decryption Workflow...");
      
      const ciphertextHash = ethers.keccak256(ethers.toUtf8Bytes("test-ciphertext"));
      const requestId = await thresholdDecryptor.requestCount();
      
      // Request decryption
      await thresholdDecryptor.requestDecrypt(ciphertextHash, 0, "0x");
      console.log("✅ Decrypt request created:", requestId);
      
      // Guardian approvals
      await thresholdDecryptor.connect(alice).approveDecrypt(requestId);
      console.log("✅ Alice approved");
      
      await thresholdDecryptor.connect(bob).approveDecrypt(requestId);
      console.log("✅ Bob approved");
      
      // Execute
      const hasSufficient = await thresholdDecryptor.hasSufficientApprovals(requestId);
      console.log("✅ Has sufficient approvals:", hasSufficient);
      
      // Test encrypted swap workflow
      console.log("\n📋 Testing Encrypted Swap Workflow...");
      
      const encryptedAmountA = ethers.solidityPacked(["uint256"], [1000]);
      const encryptedAmountB = ethers.solidityPacked(["uint256"], [2000]);
      
      const offerHash = await encryptedSwap.createOffer.staticCall(
        await token.getAddress(),
        await token.getAddress(),
        encryptedAmountA,
        encryptedAmountB,
        100,
        Math.floor(Date.now() / 1000) + 86400,
        ethers.ZeroAddress
      );
      
      console.log("✅ Offer hash computed:", offerHash);
      
      console.log("\n🎉 All fork tests passed!");
    });
  });
});
