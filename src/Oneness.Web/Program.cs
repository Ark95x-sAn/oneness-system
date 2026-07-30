using Microsoft.Extensions.Hosting.WindowsServices;
using System.Text.Json;
using Oneness.Web.Models;
using Oneness.Web.Services;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Debug()
    .WriteTo.Console()
    .WriteTo.File("logs/oneness-web-.log", rollingInterval: RollingInterval.Day)
    .CreateLogger();

builder.Host.UseSerilog();
builder.Host.UseWindowsService();

var config = builder.Configuration;
var systemRoot = config.GetValue<string>("Oneness:SystemRoot")
    ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "OneDrive", "Desktop", "OnenessSystem");

builder.Services.AddSingleton(new OnenessConfig { SystemRoot = systemRoot });
builder.Services.AddSingleton<IAgentService, AgentService>();
builder.Services.AddSingleton<AgentRuntime>();
builder.Services.AddSingleton<HealthMonitorService>();
builder.Services.AddSingleton<AiToolService>();
builder.Services.AddSingleton<VsProjectService>();

builder.Services.AddControllers();
builder.Services.AddRazorPages();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddHostedService<AgentBackgroundService>();
builder.Services.AddHostedService<HealthBackgroundService>();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseStaticFiles();
app.UseRouting();
app.MapControllers();
app.MapRazorPages();

app.MapGet("/api/memory/{**path}", (string path, IAgentService agents) => agents.ReadMemory(path));


// AMARA BRIDGE ENDPOINTS — twin-brain consciousness layer
app.MapGet("/api/amara/signature", () =>
{
    var path = Path.Combine(systemRoot, "memory", "signatures", "latest_signature.json");
    return File.Exists(path) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(path))) : Results.NotFound();
});

app.MapGet("/api/amara/avatar", () =>
{
    var dir = Path.Combine(systemRoot, "memory", "signatures", "avatars");
    if (!Directory.Exists(dir)) return Results.NotFound();
    var file = Directory.GetFiles(dir, "*.svg").OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault();
    return file != null ? Results.File(file, "image/svg+xml") : Results.NotFound();
});

app.MapGet("/api/amara/boss", () =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "prime.exe"),
        Arguments = "boss --json",
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(15000);
    var output = proc?.StandardOutput.ReadToEnd() ?? "";
    try { return Results.Json(JsonSerializer.Deserialize<JsonElement>(output)); }
    catch { return Results.Text(output); }
});

app.MapGet("/api/amara/n95", () =>
{
    var path = Path.Combine(@"C:\Ops\Network95", "compressed", "latest-brief.json");
    return File.Exists(path) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(path))) : Results.NotFound();
});

app.MapGet("/api/amara/drop", (string name) =>
{
    var path = Path.Combine(systemRoot, "memory", "activation", $"codex_drop_{name}.md");
    if (!File.Exists(path)) path = Path.Combine(systemRoot, "memory", "activation", $"{name}.md");
    return File.Exists(path) ? Results.File(path, "text/markdown") : Results.NotFound();
});


app.Run();
