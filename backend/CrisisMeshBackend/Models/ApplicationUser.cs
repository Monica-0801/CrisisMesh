using Microsoft.AspNetCore.Identity;

namespace CrisisMeshBackend.Models;

public class ApplicationUser : IdentityUser
{
    public string DisplayName { get; set; } = string.Empty;
}
