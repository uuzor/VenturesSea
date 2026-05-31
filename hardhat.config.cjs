// Use require for cofhe plugin compatibility
const cofhePlugin = require("@cofhe/hardhat-plugin");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  plugins: [cofhePlugin],
  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
          evmVersion: "cancun",
        },
      },
      {
        version: "0.8.25",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
          evmVersion: "cancun",
        },
      },
    ],
    overrides: {
      "@openzeppelin/contracts/utils/Arrays.sol": {
        version: "0.8.25",
        settings: { evmVersion: "cancun" },
      },
      "@openzeppelin/contracts/utils/Bytes.sol": {
        version: "0.8.25",
        settings: { evmVersion: "cancun" },
      },
      "@openzeppelin/contracts/utils/SafeCast.sol": {
        version: "0.8.25",
        settings: { evmVersion: "cancun" },
      },
      "@openzeppelin/contracts/utils/Arrays.sol": {
        version: "0.8.25",
        settings: { evmVersion: "cancun" },
      },
    },
  },
  networks: {
    hardhat: {
      cofeEnabled: true,
    },
  },
};
