// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FireXP} from "src/FireXP.sol";
import {EUROPToken} from "src/Europ.sol";
import {ZharChallenges} from "src/ZharChallenges.sol";

contract DeployWithTestScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        uint256 user1PrivateKey = vm.envOr("USER1_PK", uint256(0xBEEF));
        uint256 user2PrivateKey = vm.envOr("USER2_PK", uint256(0xCAFE));
        address deployer = vm.addr(deployerPrivateKey);
        address user1 = vm.addr(user1PrivateKey);
        address user2 = vm.addr(user2PrivateKey);
    
        // Deploy contracts
        vm.startBroadcast(deployerPrivateKey);
        payable(user1).transfer(1 ether);
        payable(user2).transfer(1 ether);

        FireXP fireXP = new FireXP(deployer);
        EUROPToken europ = new EUROPToken(deployer);
        ZharChallenges zharChallenges = new ZharChallenges(
            address(fireXP),
            address(europ),
            address(europ),
            deployer
        );
        fireXP.transferOwnership(address(zharChallenges));
        europ.mint(deployer, 1_000_000 ether);
        europ.mint(user1, 100_000 ether);
        europ.mint(user2, 100_000 ether);
        vm.stopBroadcast();

        // Register user1 as creator (Zharrior)
        vm.startBroadcast(user1PrivateKey);
        zharChallenges.registerCreator("Zharrior1", "ipfs://meta1");
        vm.stopBroadcast();

        // ========== SCENARIO 1: SUCCESSFUL CHALLENGE ==========
        // user2 creates a challenge for user1
        vm.startBroadcast(user2PrivateKey);
        uint256 expiration1 = block.timestamp + 48 hours;
        uint256 challengeId1 = zharChallenges.createChallenge(
            user1,
            "Do something epic!",
            expiration1,
            7000, // 70% reward
            0
        );
        europ.approve(address(zharChallenges), 10_000 ether);
        zharChallenges.depositToChallenge(challengeId1, 10_000 ether);
        vm.stopBroadcast();

        // user1 approves EUROP to zharChallenges (required for transferFrom in depositToChallenge)
        vm.startBroadcast(user1PrivateKey);
        europ.approve(address(zharChallenges), 10_000 ether);
        vm.stopBroadcast();

        // user1 submits proof
        vm.startBroadcast(user1PrivateKey);
        europ.approve(address(zharChallenges), 10_000 ether); // ensure approval for scenario 2 if needed
        zharChallenges.submitProof(challengeId1, "ipfs://proof1");
        vm.stopBroadcast();

        // user1 claims reward
        vm.startBroadcast(user1PrivateKey);
        zharChallenges.claimReward(challengeId1);
        console.log("[SUCCESS] Zharrior claimed reward for challenge 1");
        vm.stopBroadcast();

        // ========== SCENARIO 2: FAILED CHALLENGE (DISPUTED) ==========
        // user2 creates another challenge for user1
        vm.startBroadcast(user2PrivateKey);
        uint256 expiration2 = block.timestamp + 48 hours;
        uint256 challengeId2 = zharChallenges.createChallenge(
            user1,
            "Do something else!",
            expiration2,
            7000, // 70% reward
            0
        );
        europ.approve(address(zharChallenges), 10_000 ether);
        zharChallenges.depositToChallenge(challengeId2, 10_000 ether);
        vm.stopBroadcast();

        // user1 approves EUROP to zharChallenges (required for transferFrom in depositToChallenge)
        vm.startBroadcast(user1PrivateKey);
        europ.approve(address(zharChallenges), 10_000 ether);
        vm.stopBroadcast();

        // user1 submits proof
        vm.startBroadcast(user1PrivateKey);
        europ.approve(address(zharChallenges), 10_000 ether); // ensure approval for scenario 2 if needed
        zharChallenges.submitProof(challengeId2, "ipfs://proof2");
        vm.stopBroadcast();

        // user2 disputes the proof
        vm.startBroadcast(user2PrivateKey);
        zharChallenges.disputeProof(challengeId2);
        vm.stopBroadcast();

        // user2 claims refund
        vm.startBroadcast(user2PrivateKey);
        zharChallenges.claimRefund(challengeId2);
        console.log("[SUCCESS] Stoker claimed refund for challenge 2");
        vm.stopBroadcast();
    }
}
