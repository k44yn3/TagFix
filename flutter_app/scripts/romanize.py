import sys
import json

try:
    import koroman
except ImportError:
    print(json.dumps({"error": "koroman module not found"}))
    sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No text provided"}))
        sys.exit(1)
    
    text = sys.argv[1]
    try:
        romanized = koroman.romanize(text)
        print(json.dumps({"result": romanized}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)

if __name__ == "__main__":
    main()
