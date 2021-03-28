import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';

async function main() {
    const factory = await ethers.getContractFactory("Proxy");
    const proxy = await factory.deploy(process.env.TARGET_ADDRESS);

    console.log("Proxy deployed to: ", proxy.address);
    console.log("Proxy points to:   ", process.env.TARGET_ADDRESS);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error('Error:', error.msg || error);
        process.exit(1);
    });
