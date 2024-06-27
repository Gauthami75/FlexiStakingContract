require('@nomiclabs/hardhat-ethers');
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config();

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.20"
      },
      {
        version: "0.8.4"
      }
    ]
  },
  networks: {
    hardhat: {
      chainId: 1337
    },
  calibration: {
    url: "https://filecoin-calibration.chainup.net/rpc/v1",
      accounts: [process.env.PRIVATE_KEY],
      chainId: 314159 
  }
 }
};
