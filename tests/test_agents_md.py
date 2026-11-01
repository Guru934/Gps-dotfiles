#!/usr/bin/env python3
"""Verifies that AGENTS.md and related instruction files exist and are correctly configured.

This test ensures that the shared AI development rules system is properly established:
1. AGENTS.md exists and is under 120 lines
2. GEMINI.md and CLAUDE.md point to AGENTS.md
3. Cline's instruction configuration exists and is readable
"""

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

def test_agents_md_exists():
    """Verify AGENTS.md exists and is under 120 lines."""
    agents_md = REPO_ROOT / "AGENTS.md"
    
    assert agents_md.is_file(), f"AGENTS.md is missing at {agents_md}"
    
    content = agents_md.read_text(encoding="utf-8")
    lines = content.splitlines()
    
    assert len(lines) <= 120, f"AGENTS.md exceeds 120 lines ({len(lines)} lines)"
    
    # Check that it contains key project information
    required_content = ["GPS Task T1", "AGENTS.md", "mandatory safety rules"]
    for required in required_content:
        assert required in content, f"AGENTS.md missing required content: '{required}'"

def test_gemini_md_points_to_agents():
    """Verify GEMINI.md exists and points to AGENTS.md."""
    gemini_md = REPO_ROOT / "GEMINI.md"
    agents_md = REPO_ROOT / "AGENTS.md"
    
    assert gemini_md.is_file(), f"GEMINI.md is missing at {gemini_md}"
    
    content = gemini_md.read_text(encoding="utf-8")
    assert "AGENTS.md" in content, "GEMINI.md must reference AGENTS.md"
    assert "@./AGENTS.md" in content, "GEMINI.md must use @./AGENTS.md directive"

def test_claude_md_points_to_agents():
    """Verify CLAUDE.md exists and points to AGENTS.md."""
    claude_md = REPO_ROOT / "CLAUDE.md"
    agents_md = REPO_ROOT / "AGENTS.md"
    
    assert claude_md.is_file(), f"CLAUDE.md is missing at {claude_md}"
    
    content = claude_md.read_text(encoding="utf-8")
    assert "AGENTS.md" in content, "CLAUDE.md must reference AGENTS.md"
    assert "@AGENTS.md" in content, "CLAUDE.md must use @AGENTS.md directive"

def test_clinerules_exists():
    """Verify Cline's instruction configuration exists and is readable."""
    clinerules = REPO_ROOT / ".clinerules"
    
    assert clinerules.is_file(), f".clinerules is missing at {clinerules}"
    
    content = clinerules.read_text(encoding="utf-8")
    assert "AGENTS.md" in content, ".clinerules must reference AGENTS.md"
    assert "GPS Task T1" in content, ".clinerules must reference GPS Task T1"

if __name__ == "__main__":
    print("Running AGENTS.md verification tests...")
    
    test_agents_md_exists()
    print("✓ AGENTS.md exists and is under 120 lines")
    
    test_gemini_md_points_to_agents()
    print("✓ GEMINI.md correctly points to AGENTS.md")
    
    test_claude_md_points_to_agents()
    print("✓ CLAUDE.md correctly points to AGENTS.md")
    
    test_clinerules_exists()
    print("✓ .clinerules exists and is readable")
    
    print("\nAll tests passed!")