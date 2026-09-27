using CrisisMeshBackend.Data;
using CrisisMeshBackend.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CrisisMeshBackend.Controllers;

[ApiController]
[Route("api/dataset")]
public class DatasetController(CrisisMeshDbContext db) : ControllerBase
{
    [HttpGet("incidents")]
    public async Task<ActionResult<IEnumerable<DatasetIncident>>> GetIncidents(
        [FromQuery] string? status,
        [FromQuery] string? severity,
        [FromQuery] string? emergencyType,
        CancellationToken cancellationToken)
    {
        var query = db.DatasetIncidents.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(status))
            query = query.Where(x => x.Status == status);
        if (!string.IsNullOrWhiteSpace(severity))
            query = query.Where(x => x.Severity == severity);
        if (!string.IsNullOrWhiteSpace(emergencyType))
            query = query.Where(x => x.EmergencyType == emergencyType);

        return Ok(await query
            .OrderByDescending(x => x.Timestamp)
            .ToListAsync(cancellationToken));
    }

    [HttpGet("summary")]
    public async Task<ActionResult<object>> GetSummary(CancellationToken cancellationToken)
    {
        var summary = await db.DatasetIncidents
            .AsNoTracking()
            .GroupBy(x => new { x.Status, x.Severity })
            .Select(group => new
            {
                group.Key.Status,
                group.Key.Severity,
                Count = group.Count(),
            })
            .OrderBy(x => x.Status)
            .ThenBy(x => x.Severity)
            .ToListAsync(cancellationToken);

        return Ok(summary);
    }
}
