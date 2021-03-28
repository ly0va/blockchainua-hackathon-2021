import { expect, use } from 'chai';
import '@nomiclabs/hardhat-ethers';
import * as hardhat from 'hardhat';
import { ethers } from 'ethers';
import { solidity } from 'ethereum-waffle';

use(solidity);

describe('Tests', () => {
    let owner: ethers.Signer;
    let address: ethers.Signer;
    let proxy: ethers.Contract;
    let testContract: ethers.Contract;
    let foo: string;
    let bar: string;

    before('deploy target and proxy', async () => {
        [owner, address] = await hardhat.ethers.getSigners();
        let factory = await hardhat.ethers.getContractFactory('Test');
        testContract = await factory.deploy();
        factory = await hardhat.ethers.getContractFactory('Proxy');
        proxy = await factory.connect(owner).deploy(ethers.utils.hexZeroPad('0x00', 20));
        foo = testContract.interface.getSighash('foo');
        bar = testContract.interface.getSighash('bar');
    });

    it('should set target', async () => {
        expect(await proxy.getTarget()).to.eq('0x0000000000000000000000000000000000000000');
        await proxy.connect(address).setTarget(testContract.address);
        expect(await proxy.getTarget()).to.eq(testContract.address);
    });

    it('should fail calling blacklisted target', async () => {
        await expect(proxy.fallback()).to.be.revertedWith('Invalid target to call fallback on');
        await expect(proxy.fallback({ data: '0x12345678' }))
            .to.be.revertedWith('Invalid target or method');
    });

    it('should fail altering whitelist as non-owner', async () => {
        await expect(proxy.connect(address).setTargetStatus(testContract.address, true)).to.be.reverted;
    });

    it('should whitelist a method', async () => {
        await proxy.setMethodStatus(testContract.address, foo, true);
        expect(await proxy.allowedMethods(testContract.address, foo)).to.be.true;
        const five = ethers.utils.hexZeroPad('0x05', 32);
        await expect(proxy.fallback({ data: ethers.utils.concat([foo, five]) }))
            .to.emit(testContract, 'Called')
            .withArgs('foo');
    });

    it('should validate arguments', async () => {
        const factory = await hardhat.ethers.getContractFactory('AcceptEven');
        const predicate = await factory.deploy();
        await proxy.setPredicate(testContract.address, foo, predicate.address);
        expect(await proxy.predicates(testContract.address, foo)).to.eq(predicate.address);
        const five = ethers.utils.hexZeroPad('0x05', 32);
        const four = ethers.utils.hexZeroPad('0x04', 32);
        await expect(proxy.fallback({ data: ethers.utils.concat([foo, five]) }))
            .to.be.revertedWith('Invalid arguments');
        await expect(proxy.fallback({ data: ethers.utils.concat([foo, four]) }))
            .to.emit(testContract, 'Called')
            .withArgs('foo');
    });

    it('should blacklist a method', async () => {
        await proxy.setMethodStatus(testContract.address, foo, false);
        expect(await proxy.allowedMethods(testContract.address, foo)).to.be.false;
        const four = ethers.utils.hexZeroPad('0x04', 32);
        await expect(proxy.fallback({ data: ethers.utils.concat([foo, four]) }))
            .to.be.revertedWith('Invalid target or method');
    });

    it('should allow all methods on a target', async () => {
        await proxy.setTargetStatus(testContract.address, true);
        expect(await proxy.allowedTargets(testContract.address)).to.be.true;
        const four = ethers.utils.hexZeroPad('0x04', 32);
        await expect(proxy.fallback({ data: ethers.utils.concat([bar, four, four]) }))
            .to.emit(testContract, 'Called')
            .withArgs('bar');
        await expect(proxy.fallback({ value: 1 }))
            .to.emit(testContract, 'Called')
            .withArgs('receive');
    });
});
