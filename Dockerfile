FROM python:3.7-slim-buster

WORKDIR /app
RUN echo "<h1>Testing Vulnerable Image Rejection</h1>" > index.html

EXPOSE 8000
CMD ["python3", "-m", "http.server", "8000"]
