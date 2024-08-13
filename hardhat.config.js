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
      chainId: 1337,
      allowUnlimitedContractSize: true
    },
  calibration: {
    url: "https://rpc.ankr.com/filecoin_testnet",
      accounts: ['700b5a6a046b36bf908bafe524507b8892494e5f12fda5f31919eaf757e24ba8'],
      chainId: 314159 ,
      allowUnlimitedContractSize: true
  },
  tenet: {
    url: "https://tenet-evm.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
      chainId: 1559 
  },
  filecoin:{
    url:"https://api.node.glif.io",
    accounts: [process.env.PRIVATE_KEY],
    chainId: 314,
  }
 }
};
