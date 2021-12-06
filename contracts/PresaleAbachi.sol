// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

import "./SafeERC20.sol";

import "./Ownable.sol";

interface IAlphaABI {
    function mint(address account_, uint256 amount_) external;
}

contract PresaleAbachi is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 amount; // Amount DAI deposited by user
        uint256 debt; // total ABI claimed thus aABI debt
        bool claimed; // True if a user has claimed ABI
    }

    struct TeamInfo {
        uint256 numWhitelist; // number of whitelists
        uint256 amount; // Amout DAI deposited by team
        uint256 debt; // total ABI claimed thus aABI debt
        bool claimed; // True if a team member has claimed ABI
    }

    // Tokens to raise (DAI) & (FRAX) and for offer (aABI) which can be swapped for (ABI)
    IERC20 public DAI; // for user deposits
    IERC20 public FRAX; // for team deposits
    IERC20 public aABI;
    IERC20 public ABI;

    address public DAO; // Multisig treasury to send proceeds to

    address public WARCHEST; // Multisig to send team proceeds to

    uint256 public price = 20 * 1e18; // 20 DAI per ABI

    uint256 public cap = 1000 * 1e18; // 1000 DAI per whitelisted user

    uint256 public totalRaisedDAI; // total DAI raised by sale
    uint256 public totalRaisedFRAX; // total FRAX raised by sale

    uint256 public totalDebt; // total aABI and thus ABI owed to users

    bool public started; // true when sale is started

    bool public ended; // true when sale is ended

    bool public claimable; // true when sale is claimable

    bool public claimAlpha; // true when aABI is claimable

    bool public contractPaused; // circuit breaker

    mapping(address => UserInfo) public userInfo;

    mapping(address => TeamInfo) public teamInfo;

    mapping(address => bool) public whitelisted; // True if user is whitelisted

    mapping(address => bool) public whitelistedTeam; // True if team member is whitelisted

    mapping(address => uint256) public ABIClaimable; // amount of ABI claimable by address

    event Deposit(address indexed who, uint256 amount);
    event Withdraw(address token, address indexed who, uint256 amount);
    event Mint(address token, address indexed who, uint256 amount);
    event SaleStarted(uint256 block);
    event SaleEnded(uint256 block);
    event ClaimUnlocked(uint256 block);
    event ClaimAlphaUnlocked(uint256 block);
    event AdminWithdrawal(address token, uint256 amount);

    constructor(
        address _aABI,
        address _ABI,
        address _DAI,
        address _FRAX,
        address _DAO,
        address _WARCHEST
    ) {
        require( _aABI != address(0) );
        aABI = IERC20(_aABI);
        require( _ABI != address(0) );
        ABI = IERC20(_ABI);
        require( _DAI != address(0) );
        DAI = IERC20(_DAI);
        require( _FRAX != address(0) );
        FRAX = IERC20(_FRAX);
        require( _DAO != address(0) );
        DAO = _DAO;
        require( _WARCHEST != address(0) );
        WARCHEST = _WARCHEST;
    }

    //* @notice modifer to check if contract is paused
    modifier checkIfPaused() {
        require(contractPaused == false, "contract is paused");
        _;
    }
    /**
     *  @notice adds a single whitelist to the sale
     *  @param _address: address to whitelist
     */
    function addWhitelist(address _address) external onlyOwner {
        whitelisted[_address] = true;
    }

    /**
     *  @notice adds multiple whitelist to the sale
     *  @param _addresses: dynamic array of addresses to whitelist
     */
    function addMultipleWhitelist(address[] calldata _addresses) external onlyOwner {
        require(_addresses.length <= 333,"too many addresses");
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelisted[_addresses[i]] = true;
        }
    }

    /**
     *  @notice removes a single whitelist from the sale
     *  @param _address: address to remove from whitelist
     */
    function removeWhitelist(address _address) external onlyOwner {
        whitelisted[_address] = false;
    }
    /**
     *  @notice adds a team member from sale
     *  @param _address: address to whitelist
     *  @param _numWhitelist: number of whitelists for address
     */
    function addTeam(address _address, uint256 _numWhitelist) external onlyOwner {
        require(_numWhitelist != 0, "cannot set zero whitelists");
        whitelistedTeam[_address] = true;
        teamInfo[_address].numWhitelist = _numWhitelist;
    }

    /**
     *  @notice removes a team member from sale
     *  @param _address: address to remove from whitelist
     */
    function removeTeam(address _address) external onlyOwner {
        whitelistedTeam[_address] = false;
        delete teamInfo[_address];
    }

    // @notice Starts the sale
    function start() external onlyOwner {
        require(!started, "Sale has already started");
        started = true;
        emit SaleStarted(block.number);
    }

    // @notice Ends the sale
    function end() external onlyOwner {
        require(started, "Sale has not started");
        require(!ended, "Sale has already ended");
        ended = true;
        emit SaleEnded(block.number);
    }

    // @notice lets users claim ABI
    // @dev send sufficient ABI before calling
    function claimUnlock() external onlyOwner {
        require(ended, "Sale has not ended");
        require(!claimable, "Claim has already been unlocked");
        require(ABI.balanceOf(address(this)) >= totalDebt, 'not enough ABI in contract');
        claimable = true;
        emit ClaimUnlocked(block.number);
    }


    // @notice lets users claim aABI
    function claimAlphaUnlock() external onlyOwner {
        require(claimable, "Claim has not been unlocked");
        require(!claimAlpha, "Claim Alpha has already been unlocked");
        claimAlpha = true;
        emit ClaimAlphaUnlocked(block.number);
    }

    // @notice lets owner pause contract
    function togglePause() external onlyOwner returns (bool){
        contractPaused = !contractPaused;
        return contractPaused;
    }
    /**
     *  @notice transfer ERC20 token to DAO multisig
     *  @param _token: token address to withdraw
     *  @param _amount: amount of token to withdraw
     */
    function adminWithdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20( _token ).safeTransfer( address(msg.sender), _amount );
        emit AdminWithdrawal(_token, _amount);
    }

    /**
     *  @notice it deposits DAI for the sale
     *  @param _amount: amount of DAI to deposit to sale (18 decimals)
     */
    function deposit(uint256 _amount) external checkIfPaused {
        require(started, 'Sale has not started');
        require(!ended, 'Sale has ended');
        require(whitelisted[msg.sender] == true, 'msg.sender is not whitelisted user');
        require(_amount == cap, 'Deposit must equal 1000 DAI');
        UserInfo storage user = userInfo[msg.sender];

        require(
            cap >= user.amount.add(_amount),
            'new amount above user limit'
            );

        user.amount = user.amount.add(_amount);
        totalRaisedDAI = totalRaisedDAI.add(_amount);

        uint256 payout = _amount.mul(1e18).div(price).div(1e9); // aABI to mint for _amount

        totalDebt = totalDebt.add(payout);

        DAI.safeTransferFrom( msg.sender, DAO, _amount );

        IAlphaABI( address(aABI) ).mint( msg.sender, payout );

        emit Deposit(msg.sender, _amount);
    }
    /**
     *  @notice it deposits FRAX for the sale
     *  @param _amount: amount of FRAX to deposit to sale (18 decimals)
     *  @dev only for team members
     */
    function depositTeam(uint256 _amount) external checkIfPaused {
        require(started, 'Sale has not started');
        require(!ended, 'Sale has ended');
        require(whitelistedTeam[msg.sender] == true, 'msg.sender is not whitelisted team');

        TeamInfo storage team = teamInfo[msg.sender];

        require(
            cap.mul(team.numWhitelist) >= team.amount.add(_amount),
            'new amount above team limit'
            );

        team.amount = team.amount.add(_amount);
        totalRaisedFRAX = totalRaisedFRAX.add(_amount);

        uint256 payout = _amount.mul(1e18).div(price).div(1e9); // ABI debt to claim

        totalDebt = totalDebt.add(payout);

        FRAX.safeTransferFrom( msg.sender, DAO, _amount );

        IAlphaABI( address(aABI) ).mint( WARCHEST, payout );

        emit Deposit(msg.sender, _amount);
    }

    /**
     *  @notice it deposits aABI to withdraw ABI from the sale
     *  @param _amount: amount of aABI to deposit to sale (9 decimals)
     */
    function withdraw(uint256 _amount) external checkIfPaused {
        require(claimable, 'ABI is not yet claimable');
        require(_amount > 0, '_amount must be greater than zero');

        UserInfo storage user = userInfo[msg.sender];

        user.debt = user.debt.add(_amount);

        totalDebt = totalDebt.sub(_amount);

        aABI.safeTransferFrom( msg.sender, address(this), _amount );

        ABI.safeTransfer( msg.sender, _amount );

        emit Mint(address(aABI), msg.sender, _amount);
        emit Withdraw(address(ABI), msg.sender, _amount);
    }

    // @notice it checks a users DAI allocation remaining
    function getUserRemainingAllocation(address _user) external view returns ( uint256 ) {
        UserInfo memory user = userInfo[_user];
        return cap.sub(user.amount);
    }
    // @notice it claims aABI back from the sale
    function claimAlphaABI() external checkIfPaused {
        require(claimAlpha, 'aABI is not yet claimable');

        UserInfo storage user = userInfo[msg.sender];

        require(user.debt > 0, 'msg.sender has not participated');
        require(!user.claimed, 'msg.sender has already claimed');

        user.claimed = true;

        uint256 payout = user.debt;
        user.debt = 0;

        aABI.safeTransfer( msg.sender, payout );

        emit Withdraw(address(aABI),msg.sender, payout);
    }

}
