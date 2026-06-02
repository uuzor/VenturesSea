const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Simple Test", function () {
  it("should deploy contracts", async function () {
    const [owner] = await ethers.getSigners();
    console.log("Owner:", owner.address);
    
    // Get factory
    const IdeaVault = await ethers.getContractFactory("IdeaVault");
    console.log("IdeaVault factory created");
    
    // Deploy with proper waiting
    const vault = await IdeaVault.deploy();
    await vault.waitForDeployment();
    const addr = await vault.getAddress();
    console.log("Vault deployed at:", addr);
    
    expect(addr).to.not.equal("0x0000000000000000000000000000000000000000");
  });
});
