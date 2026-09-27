
using CrisisMeshBackend.Data;
using CrisisMeshBackend.Models;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Identity;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddOpenApi();
builder.Services.AddDbContext<CrisisMeshDbContext>(options =>
    options.UseSqlite("Data Source=crisismesh.db"));
builder.Services.AddDbContext<AuthDbContext>(options =>
    options.UseSqlite("Data Source=crisismesh-auth.db"));
builder.Services.AddIdentityCore<ApplicationUser>(options =>
    {
        options.Password.RequiredLength = 8;
        options.User.RequireUniqueEmail = true;
    })
    .AddRoles<IdentityRole>()
    .AddEntityFrameworkStores<AuthDbContext>()
    .AddSignInManager();
builder.Services.AddAuthentication(IdentityConstants.ApplicationScheme)
    .AddIdentityCookies();
builder.Services.AddAuthorization();
builder.Services.AddScoped<DatasetImporter>();

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<CrisisMeshDbContext>();
    db.Database.EnsureCreated();
    try
    {
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE Incidents ADD COLUMN ClientEventId TEXT NULL");
    }
    catch (SqliteException exception) when (
        exception.SqliteErrorCode == 1 &&
        exception.Message.Contains("duplicate column name", StringComparison.OrdinalIgnoreCase))
    {
        // Existing databases already contain the compatibility column.
    }

    db.Database.ExecuteSqlRaw(
        "CREATE UNIQUE INDEX IF NOT EXISTS IX_Incidents_ClientEventId " +
        "ON Incidents (ClientEventId) WHERE ClientEventId IS NOT NULL");
    db.Database.ExecuteSqlRaw("""
        CREATE TABLE IF NOT EXISTS DatasetIncidents (
            Id INTEGER NOT NULL CONSTRAINT PK_DatasetIncidents PRIMARY KEY AUTOINCREMENT,
            IncidentId TEXT NOT NULL,
            Timestamp TEXT NOT NULL,
            EmergencyType TEXT NOT NULL,
            Message TEXT NOT NULL,
            Latitude REAL NOT NULL,
            Longitude REAL NOT NULL,
            LocationName TEXT NOT NULL,
            Severity TEXT NOT NULL,
            PeopleAffected INTEGER NOT NULL,
            PhotoAttached INTEGER NOT NULL,
            PhotoPath TEXT NULL,
            Status TEXT NOT NULL,
            RetryCount INTEGER NOT NULL,
            NetworkAvailable INTEGER NOT NULL,
            CreatedAt TEXT NOT NULL,
            LastAttemptAt TEXT NULL,
            ServerIncidentId TEXT NULL
        )
        """);
    db.Database.ExecuteSqlRaw(
        "CREATE UNIQUE INDEX IF NOT EXISTS IX_DatasetIncidents_IncidentId " +
        "ON DatasetIncidents (IncidentId)");

    var importer = scope.ServiceProvider.GetRequiredService<DatasetImporter>();
    await importer.ImportAsync(CancellationToken.None);

    var authDb = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
    await authDb.Database.EnsureCreatedAsync();
    var roleManager = scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>();
    foreach (var role in new[] { "Admin", "Rescue", "CommonUser" })
    {
        if (!await roleManager.RoleExistsAsync(role))
            await roleManager.CreateAsync(new IdentityRole(role));
    }

    var userManager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
    await SeedDemoUserAsync(
        userManager,
        configuration: app.Configuration,
        "RescueEmail",
        "RescuePassword",
        "Rescue",
        "Rescue Team");
    await SeedDemoUserAsync(
        userManager,
        configuration: app.Configuration,
        "AdminEmail",
        "AdminPassword",
        "Admin",
        "CrisisMesh Administrator");
}

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.UseDefaultFiles();
app.UseStaticFiles();

app.Run();

static async Task SeedDemoUserAsync(
    UserManager<ApplicationUser> userManager,
    IConfiguration configuration,
    string emailKey,
    string passwordKey,
    string role,
    string displayName)
{
    var email = configuration[$"DemoUsers:{emailKey}"];
    var password = configuration[$"DemoUsers:{passwordKey}"];
    if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password))
        return;

    var user = await userManager.FindByEmailAsync(email);
    if (user is null)
    {
        user = new ApplicationUser
        {
            UserName = email,
            Email = email,
            DisplayName = displayName,
            EmailConfirmed = true,
        };
        var result = await userManager.CreateAsync(user, password);
        if (!result.Succeeded)
            throw new InvalidOperationException(
                $"Could not create demo {role} account: " +
                string.Join("; ", result.Errors.Select(error => error.Description)));
    }

    if (!await userManager.IsInRoleAsync(user, role))
        await userManager.AddToRoleAsync(user, role);
}
