// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FireXP} from "src/FireXP.sol";
import {EUROPToken} from "src/Europ.sol";
import {ZharChallenges} from "src/ZharChallenges.sol";

contract DeployScript is Script {
  function setUp() public {}

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
    address deployer = vm.addr(deployerPrivateKey);
    vm.startBroadcast(deployerPrivateKey);
    console.log("Deploying FireXP contract...");
    FireXP fireXP = new FireXP(deployer);
    EUROPToken europ = new EUROPToken(deployer);
    console.log("FireXP contract deployed at:", address(fireXP));
    ZharChallenges zharChallenges = new ZharChallenges(
      address(fireXP),
      address(europ),
      address(europ),
      deployer
    );
    fireXP.transferOwnership(address(zharChallenges));
    console.log("ZharChallenges contract deployed at:", address(zharChallenges));
    europ.mint(deployer, 1000000 ether);
    console.log("Minted 1,000,000 EUROP tokens to deployer:", deployer);
    vm.stopBroadcast();
  }
}
