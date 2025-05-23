import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFireXp is IERC20{
    function mint(address to, uint256 amount) external;
}