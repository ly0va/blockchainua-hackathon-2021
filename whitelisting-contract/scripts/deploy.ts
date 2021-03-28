import '@nomiclabs/hardhat-ethers';
import * as hardhat from 'hardhat';
import { ethers } from 'hardhat';

async function main() {
    const [deployer, minter] = await hardhat.ethers.getSigners();
    let factory = await hardhat.ethers.getContractFactory('ERC20Token');
    const zkam = await factory.connect(deployer).deploy(minter.getAddress(), minter.getAddress());
    factory = await ethers.getContractFactory("Timelock");
    const timelock = await factory.deploy(deployer.getAddress(), deployer.getAddress());
    factory = await ethers.getContractFactory("Proxy");
    const proxy = await factory.deploy(process.env.TARGET_ADDRESS, deployer.getAddress());
    factory = await ethers.getContractFactory("Governance");
    const governance = await factory.deploy(timelock.address, zkam.address, proxy.address);

    console.log("Proxy deployed to: ", proxy.address);
    console.log("ZKM deployed to: ", zkam.address);
    console.log("Timelock deployed to: ", timelock.address);
    console.log("Governance deployed to: ", governance.address);
    console.log("Proxy points to:   ", process.env.TARGET_ADDRESS);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error('Error:', error.msg || error);
        process.exit(1);
    });
