"""Reuse the review interaction checks without rewriting earlier evidence."""
from pathlib import Path
import verify_actor_refinement_review as review

review.OUT = Path(__file__).resolve().parents[1] / "artifacts/verification/actor-rig-drawings-20261115/review-browser"
review.URL = (review.OUT.parent / "review/index.html").as_uri()

if __name__ == "__main__":
    review.main()
