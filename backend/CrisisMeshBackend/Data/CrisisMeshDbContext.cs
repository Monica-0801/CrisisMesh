using CrisisMeshBackend.Models;
using Microsoft.EntityFrameworkCore;

namespace CrisisMeshBackend.Data;

public class CrisisMeshDbContext(DbContextOptions<CrisisMeshDbContext> options) : DbContext(options)
{
    public DbSet<SosIncident> Incidents => Set<SosIncident>();
    public DbSet<DatasetIncident> DatasetIncidents => Set<DatasetIncident>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<SosIncident>()
            .HasIndex(x => x.ClientEventId)
            .IsUnique();
        modelBuilder.Entity<DatasetIncident>()
            .HasIndex(x => x.IncidentId)
            .IsUnique();
    }
}
