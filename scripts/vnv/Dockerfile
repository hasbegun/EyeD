FROM python:3.12-slim

WORKDIR /vnv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY benchmark.py analyze.py report.py profile.py ./

ENTRYPOINT ["python"]
