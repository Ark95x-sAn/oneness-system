"""Prime Fire Council CLI entry point."""
from __future__ import annotations

import argparse
import sys
from . import __version__
from . import commands


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="prime",
        description="Prime Fire Council — command center for the Oneness System",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")

    sub = parser.add_subparsers(dest="command", help="Commands")

    sub.add_parser("doctor", help="Diagnose Oneness System readiness")
    sub.add_parser("start", help="Start Prime Fire Council (web + orchestrator)")
    sub.add_parser("stop", help="Stop Oneness web and orchestrator processes")
    sub.add_parser("status", help="Show system status")
    sub.add_parser("web", help="Open Oneness Web dashboard")
    sub.add_parser("fix", help="Run all fixer agents")
    sub.add_parser("auth", help="Launch AI tool authentication helpers")
    sub.add_parser("service-install", help="Install Windows service (requires admin UAC)")
    sub.add_parser("apps", help="List targetable Windows apps (requires Computer Use)")

    agents = sub.add_parser("agents", help="Agent operations")
    agents_sub = agents.add_subparsers(dest="agents_command")
    agents_sub.add_parser("list", help="List agents")
    agents_tick = agents_sub.add_parser("tick", help="Tick one agent")
    agents_tick.add_argument("agent_id", help="Agent ID to tick")

    projects = sub.add_parser("projects", help="Project operations")
    projects_sub = projects.add_subparsers(dest="projects_command")
    projects_sub.add_parser("list", help="List scanned projects")
    projects_sub.add_parser("scan", help="Trigger VS project scan")
    build_cmd = projects_sub.add_parser("build", help="Build a project")
    build_cmd.add_argument("path", help="Path to project file or directory")
    build_cmd.add_argument("--config", default="Release", help="Build configuration")

    skill = sub.add_parser("skill-install", help="Install a skill from openai/skills repo")
    skill.add_argument("path", help="Skill path, e.g. skills/.curated/some-skill")

    aura = sub.add_parser("aura", help="Aura ambient subagent control")
    aura_sub = aura.add_subparsers(dest="aura_command")
    aura_sub.add_parser("start", help="Start all Aura subagents")
    aura_sub.add_parser("stop", help="Stop all Aura subagents")
    aura_sub.add_parser("status", help="Show Aura subagent status")
    aura_sub.add_parser("state", help="Show latest Aura state")
    aura_sub.add_parser("logs", help="List Aura subagent logs")

    finance = sub.add_parser("finance", help="Finance and compounding tools")
    finance_sub = finance.add_subparsers(dest="finance_command")
    finance_sub.add_parser("markets", help="Fetch top Polymarket opportunities")
    compound_cmd = finance_sub.add_parser("compound", help="Compound interest calculator")
    compound_cmd.add_argument("principal", type=float, help="Starting principal")
    compound_cmd.add_argument("rate", type=float, help="Annual rate as decimal (e.g. 0.10 for 10%)")
    compound_cmd.add_argument("years", type=float, help="Number of years")
    compound_cmd.add_argument("--contributions", type=float, default=0.0, help="Monthly contributions")

    sigil = sub.add_parser("852", help="Activate the 852 anti-self-sabotage sigil")
    sigil.add_argument("--intent", default="rise", help="Intent for this resonance")

    gates = sub.add_parser("gates", help="Evaluate progression gates and bosses")
    boss = sub.add_parser("boss", help="Show current gate boss")
    sabotage = sub.add_parser("sabotage", help="Detect self-sabotage patterns")

    review = sub.add_parser("review", help="Lightweight static review of a path")
    sub.add_parser("speedup", help="Launch PC optimization (admin UAC required for deep cleanup")
    review.add_argument("target", help="File or directory to review")

    return parser


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    json_mode = "--json" in argv
    argv = [a for a in argv if a != "--json"]
    parser = build_parser()
    args = parser.parse_args(argv)

    if not args.command:
        parser.print_help()
        return 0

    try:
        if args.command == "doctor":
            commands.cmd_doctor(json_mode)
        elif args.command == "start":
            commands.cmd_start(json_mode)
        elif args.command == "stop":
            commands.cmd_stop()
        elif args.command == "status":
            commands.cmd_status(json_mode)
        elif args.command == "web":
            commands.cmd_web()
        elif args.command == "fix":
            commands.cmd_fix(json_mode)
        elif args.command == "auth":
            commands.cmd_auth()
        elif args.command == "service-install":
            commands.cmd_service_install()
        elif args.command == "apps":
            commands.cmd_apps_list()
        elif args.command == "agents":
            if args.agents_command == "list":
                commands.cmd_agents_list(json_mode)
            elif args.agents_command == "tick":
                commands.cmd_agents_tick(args.agent_id, json_mode)
            else:
                print("Use: prime agents {list|tick}")
        elif args.command == "projects":
            if args.projects_command == "list":
                commands.cmd_status(json_mode)
            elif args.projects_command == "scan":
                commands.cmd_scan(json_mode)
            elif args.projects_command == "build":
                commands.cmd_build(args.path, args.config, json_mode)
            else:
                print("Use: prime projects {list|scan|build}")
        elif args.command == "skill-install":
            commands.cmd_install_skill(args.path)
        elif args.command == "speedup":
            commands.cmd_speedup(json_mode)
        elif args.command == "aura":
            if args.aura_command:
                commands.cmd_aura(args.aura_command, json_mode)
            else:
                print("Use: prime aura {start|stop|status|state|logs}")
        elif args.command == "finance":
            if args.finance_command == "markets":
                commands.cmd_markets(json_mode)
            elif args.finance_command == "compound":
                commands.cmd_compound(args.principal, args.rate, args.years, args.contributions, json_mode)
            else:
                print("Use: prime finance {markets|compound}")
        elif args.command == "852":
            commands.cmd_852(args.intent, json_mode)
        elif args.command == "gates":
            commands.cmd_gates(json_mode)
        elif args.command == "boss":
            commands.cmd_boss(json_mode)
        elif args.command == "sabotage":
            commands.cmd_sabotage(json_mode)
        elif args.command == "review":
            commands.cmd_review(args.target, json_mode)
        else:
            parser.print_help()
    except Exception as e:
        if json_mode:
            import json
            print(json.dumps({"ok": False, "error": str(e)}))
        else:
            print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
