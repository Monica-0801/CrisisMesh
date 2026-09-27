using CrisisMeshBackend.Data;
using CrisisMeshBackend.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CrisisMeshBackend.Controllers;

[ApiController]
[Route("api")]
public class SosController(CrisisMeshDbContext db) : ControllerBase
{
    [HttpPost("incidents")]
    public async Task<ActionResult<SosIncident>> CreateIncident(
        [FromBody] SosIncident incident,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(incident.Message))
        {
            return ValidationProblem("Emergency message is required.");
        }

        if (!string.IsNullOrWhiteSpace(incident.ClientEventId))
        {
            var existing = await db.Incidents
                .SingleOrDefaultAsync(
                    x => x.ClientEventId == incident.ClientEventId,
                    cancellationToken);
            if (existing is not null)
            {
                return Ok(existing);
            }
        }

        incident.Id = 0;
        incident.DeviceId = string.IsNullOrWhiteSpace(incident.DeviceId)
            ? "crisismesh-android"
            : incident.DeviceId;
        incident.RelayMode = string.IsNullOrWhiteSpace(incident.RelayMode)
            ? "mesh"
            : incident.RelayMode;
        incident.Status = "received";
        incident.DangerType = ClassifyDanger(incident.Message);
        incident.Priority = incident.DangerType is "Fire / smoke emergency" or "Medical emergency"
            ? 1
            : incident.DangerType is "Security threat" or "Accident / crash" ? 2 : 3;
        incident.CreatedAt = incident.CreatedAt == default
            ? DateTimeOffset.UtcNow
            : incident.CreatedAt;

        db.Incidents.Add(incident);
        await db.SaveChangesAsync(cancellationToken);
        return CreatedAtAction(nameof(GetIncident), new { id = incident.Id }, incident);
    }

    [HttpGet("incidents")]
    public async Task<ActionResult<IEnumerable<SosIncident>>> GetIncidents(
        CancellationToken cancellationToken)
    {
        var incidents = await db.Incidents
            .OrderBy(x => x.Priority)
            .ThenByDescending(x => x.Id)
            .ToListAsync(cancellationToken);
        return Ok(incidents);
    }

    [HttpGet("incidents/{id:int}")]
    public async Task<ActionResult<SosIncident>> GetIncident(
        int id,
        CancellationToken cancellationToken)
    {
        var incident = await db.Incidents.FindAsync([id], cancellationToken);
        return incident is null ? NotFound() : Ok(incident);
    }

    [HttpPatch("incidents/{id:int}/status")]
    public async Task<IActionResult> UpdateStatus(
        int id,
        [FromBody] StatusUpdate update,
        CancellationToken cancellationToken)
    {
        var incident = await db.Incidents.FindAsync([id], cancellationToken);
        if (incident is null)
        {
            return NotFound();
        }

        incident.Status = update.Status;
        await db.SaveChangesAsync(cancellationToken);
        return Ok(incident);
    }

    private static string ClassifyDanger(string message)
    {
        var text = message.ToLowerInvariant();
        if (text.Contains("fire") || text.Contains("smoke") || text.Contains("explosion"))
            return "Fire / smoke emergency";
        if (text.Contains("medical") || text.Contains("bleeding") || text.Contains("injury") || text.Contains("pain"))
            return "Medical emergency";
        if (text.Contains("accident") || text.Contains("crash") || text.Contains("vehicle") || text.Contains("fall"))
            return "Accident / crash";
        if (text.Contains("flood") || text.Contains("earthquake") || text.Contains("storm") || text.Contains("landslide"))
            return "Natural disaster";
        if (text.Contains("attack") || text.Contains("robbery") || text.Contains("danger") || text.Contains("gun"))
            return "Security threat";
        if (text.Contains("trapped") || text.Contains("stuck") || text.Contains("help"))
            return "Rescue / trapped situation";
        return "General emergency";
    }
}

public record StatusUpdate(string Status);
