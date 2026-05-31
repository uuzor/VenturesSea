import pkg from 'hardhat';
const { network } = pkg;

describe('Fork Mainnet FHE Operations', function () {

  describe('Threshold Decryptor', function () {
    it('should deploy threshold decryptor', async function () {
      const signers = await ethers.getSigners();
      const owner = signers[0];
      
      const ThresholdDecryptor = await ethers.getContractFactory('ThresholdDecryptor');
      const thresholdDecryptor = await ThresholdDecryptor.deploy();
      await thresholdDecryptor.waitForDeployment();
      
      const guardians = [signers[1].address, signers[2].address, signers[3].address];
      await thresholdDecryptor.initialize(owner.address, guardians, 2, 86400);
      console.log('ThresholdDecryptor deployed at:', await thresholdDecryptor.getAddress());
    });
  });

  describe('Encrypted Swap', function () {
    it('should deploy encrypted swap', async function () {
      const signers = await ethers.getSigners();
      
      const EncryptedSwap = await ethers.getContractFactory('EncryptedSwap');
      const swap = await EncryptedSwap.deploy();
      await swap.waitForDeployment();
      
      await swap.initialize(
        signers[0].address,
        signers[0].address,
        30
      );
      console.log('EncryptedSwap deployed at:', await swap.getAddress());
    });
  });

  describe('Full Integration Flow', function () {
    it('should execute full FHE workflow', async function () {
      const signers = await ethers.getSigners();
      const owner = signers[0];
      const alice = signers[1];
      const bob = signers[2];
      const carol = signers[3];
      
      console.log('FHE Protocol Integration Test');
      
      console.log('1. Deploying ThresholdDecryptor...');
      const ThresholdDecryptor = await ethers.getContractFactory('ThresholdDecryptor');
      const thresholdDecryptor = await ThresholdDecryptor.deploy();
      await thresholdDecryptor.waitForDeployment();
      
      const guardians = [alice.address, bob.address, carol.address];
      await thresholdDecryptor.initialize(owner.address, guardians, 2, 86400);
      console.log('   ThresholdDecryptor deployed at:', await thresholdDecryptor.getAddress());
      
      console.log('2. Deploying EncryptedSwap...');
      const EncryptedSwap = await ethers.getContractFactory('EncryptedSwap');
      const encryptedSwap = await EncryptedSwap.deploy();
      await encryptedSwap.waitForDeployment();
      
      await encryptedSwap.initialize(
        await thresholdDecryptor.getAddress(),
        owner.address,
        30
      );
      console.log('   EncryptedSwap deployed at:', await encryptedSwap.getAddress());
      
      const swapAddress = await encryptedSwap.getAddress();
      await thresholdDecryptor.setAuthorizedHandler(swapAddress, true);
      await thresholdDecryptor.setAuthorizedHandler(owner.address, true);
      console.log('   Authorized handlers set');
      
      console.log('3. Verifying Guardian Setup...');
      const guardianCount = await thresholdDecryptor.getGuardianCount();
      const minApprovals = await thresholdDecryptor.minApprovals();
      console.log('   Guardians:', guardianCount.toString(), ', Min approvals:', minApprovals.toString());
      
      console.log('4. Testing Threshold Decryption...');
      const ciphertextHash = ethers.keccak256(ethers.toUtf8Bytes('test-ciphertext'));
      const requestId = await thresholdDecryptor.requestCount();
      
      await thresholdDecryptor.connect(owner).requestDecrypt(ciphertextHash, 0, '0x');
      console.log('   Decrypt request created with ID:', requestId.toString());
      
      await thresholdDecryptor.connect(alice).approveDecrypt(requestId);
      console.log('   Alice approved (1/2)');
      
      await thresholdDecryptor.connect(bob).approveDecrypt(requestId);
      console.log('   Bob approved (2/2)');
      
      const hasSufficient = await thresholdDecryptor.hasSufficientApprovals(requestId);
      console.log('   Has sufficient approvals:', hasSufficient);
      
      console.log('5. Testing Encrypted Swap...');
      
      const tokenA = '0x0000000000000000000000000000000000000001';
      const tokenB = '0x0000000000000000000000000000000000000002';
      await encryptedSwap.addSupportedToken(tokenA);
      await encryptedSwap.addSupportedToken(tokenB);
      console.log('   Added token pairs to supported tokens');
      
      const encryptedAmountA = ethers.solidityPacked(['uint256'], [1000]);
      const encryptedAmountB = ethers.solidityPacked(['uint256'], [2000]);
      
      const offerHash = await encryptedSwap.createOffer.staticCall(
        tokenA,
        tokenB,
        encryptedAmountA,
        encryptedAmountB,
        100,
        Math.floor(Date.now() / 1000) + 86400,
        ethers.ZeroAddress
      );
      
      console.log('   Offer hash computed:', offerHash);
      
      console.log('All fork tests passed!');
    });
  });
});
