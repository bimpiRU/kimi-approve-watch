FROM node:24-alpine
WORKDIR /app
COPY package.json server.js ./
COPY lib ./lib
COPY public ./public
# data/ (settings, sessions) и runs/ монтируются томами при необходимости
ENV PORT=8787 HOST=0.0.0.0
EXPOSE 8787
CMD ["node", "server.js"]
