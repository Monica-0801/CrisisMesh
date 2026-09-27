using CrisisMeshBackend.Models;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;

namespace CrisisMeshBackend.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(
    UserManager<ApplicationUser> userManager,
    SignInManager<ApplicationUser> signInManager) : ControllerBase
{
    [HttpGet("me")]
    public IActionResult Me() =>
        User.Identity?.IsAuthenticated == true
            ? Ok(new { authenticated = true, user = User.Identity.Name, role = User.FindFirst("role")?.Value })
            : Unauthorized(new { authenticated = false });

    [HttpPost("register")]
    public async Task<IActionResult> Register(RegisterRequest request)
    {
        if (!Enum.TryParse<UserRole>(request.Role, true, out var role) ||
            role != UserRole.CommonUser)
            return BadRequest(new { message = "Only Common User accounts can self-register." });

        var user = new ApplicationUser
        {
            UserName = request.Email,
            Email = request.Email,
            DisplayName = request.DisplayName,
        };
        var result = await userManager.CreateAsync(user, request.Password);
        if (!result.Succeeded)
            return BadRequest(new { message = string.Join(" ", result.Errors.Select(x => x.Description)) });

        await userManager.AddToRoleAsync(user, role.ToString());
        return Ok(new { message = "Account created." });
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginRequest request)
    {
        var user = await userManager.FindByEmailAsync(request.Email);
        if (user is null || !await userManager.CheckPasswordAsync(user, request.Password))
            return Unauthorized(new { message = "Invalid email or password." });

        var roles = await userManager.GetRolesAsync(user);
        var role = roles.FirstOrDefault() ?? "CommonUser";
        if (!string.IsNullOrWhiteSpace(request.RequestedRole) &&
            !string.Equals(role, request.RequestedRole, StringComparison.OrdinalIgnoreCase))
        {
            return Forbid();
        }
        await signInManager.SignInWithClaimsAsync(
            user,
            isPersistent: false,
            [new System.Security.Claims.Claim("role", role)]);
        return Ok(new { role });
    }

    [HttpPost("logout")]
    public async Task<IActionResult> Logout()
    {
        await signInManager.SignOutAsync();
        return NoContent();
    }
}

public record LoginRequest(string Email, string Password, string? RequestedRole = null);
public record RegisterRequest(string Email, string Password, string DisplayName, string Role);
public enum UserRole { Admin, Rescue, CommonUser }
