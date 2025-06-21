###############################
# 第一阶段：构建 .NET 程序
###############################
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:9.0-bookworm-slim AS build-dotnet
WORKDIR /root/build
# 如果需要针对目标架构编译，可使用 ARG TARGETARCH
ARG TARGETARCH

# 将 c 目录下的 .NET 项目复制到构建目录中
COPY c/ ./

# 执行发布命令，将 Lagrange.OneBot 项目编译并发布到 /root/out 目录
RUN dotnet publish -p:DebugType="none" -a $TARGETARCH -f "net9.0" -o /root/out Lagrange.OneBot

###############################
# 第二阶段：构建最终镜像（合并 .NET 与 Python 环境）
###############################
FROM python:3.11-slim

# 安装所需工具、Microsoft 的 apt 源、.NET 运行时、supervisor 以及构建 Python 所需依赖
RUN apt-get update && \
    apt-get install -y wget apt-transport-https gnupg ca-certificates && \
    wget https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y dotnet-runtime-9.0 supervisor gosu gcc build-essential python3-dev libffi-dev libssl-dev && \
    rm -rf /var/lib/apt/lists/*

###############################
# 复制 .NET 应用文件
###############################
WORKDIR /app
# 从第一阶段复制发布后的 .NET 程序到 /app/bin 目录
COPY --from=build-dotnet /root/out /app/bin
# 同时复制 docker-entrypoint.sh（确保此脚本在 c/Lagrange.OneBot/Resources/ 目录下）
COPY c/Lagrange.OneBot/Resources/docker-entrypoint.sh /app/bin/docker-entrypoint.sh
# 添加执行权限
RUN chmod +x /app/bin/docker-entrypoint.sh

###############################
# 安装 Python 应用
###############################
WORKDIR /app
# 将 python 目录下的所有文件复制到容器内 /app 目录
COPY python/ /app/
# 修改 /app 目录的权限为默认非 root 用户（一般为 uid:1000），确保运行时可以读写文件
RUN chown -R 1000:1000 /app

# 升级 pip 并安装 requirements.txt 中的依赖（无缓存安装），以及额外依赖 socksio、wechatpy、cryptography
RUN python -m pip install --upgrade pip --root-user-action=ignore && \
    pip install -r requirements.txt --no-cache-dir --root-user-action=ignore && \
    pip install socksio wechatpy cryptography --no-cache-dir --root-user-action=ignore

# 暴露 Python 应用监听的端口
EXPOSE 6185
EXPOSE 6186

###############################
# 添加 supervisord 配置文件
###############################
# 配置 supervisord 同时启动 .NET 和 Python 应用
RUN echo "[supervisord]" > /etc/supervisord.conf && \
    echo "nodaemon=true" >> /etc/supervisord.conf && \
    echo "logfile=/dev/stdout" >> /etc/supervisord.conf && \
    echo "logfile_maxbytes=0" >> /etc/supervisord.conf && \
    echo "loglevel=info" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[program:dotnet]" >> /etc/supervisord.conf && \
    echo "command=/app/bin/docker-entrypoint.sh" >> /etc/supervisord.conf && \
    echo "autostart=true" >> /etc/supervisord.conf && \
    echo "autorestart=true" >> /etc/supervisord.conf && \
    echo "stdout_logfile=/dev/stdout" >> /etc/supervisord.conf && \
    echo "stdout_logfile_maxbytes=0" >> /etc/supervisord.conf && \
    echo "stderr_logfile=/dev/stderr" >> /etc/supervisord.conf && \
    echo "stderr_logfile_maxbytes=0" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[program:python]" >> /etc/supervisord.conf && \
    echo "command=python /app/main.py" >> /etc/supervisord.conf && \
    echo "directory=/app" >> /etc/supervisord.conf && \
    echo "autostart=true" >> /etc/supervisord.conf && \
    echo "autorestart=true" >> /etc/supervisord.conf && \
    echo "stdout_logfile=/dev/stdout" >> /etc/supervisord.conf && \
    echo "stdout_logfile_maxbytes=0" >> /etc/supervisord.conf && \
    echo "stderr_logfile=/dev/stderr" >> /etc/supervisord.conf && \
    echo "stderr_logfile_maxbytes=0" >> /etc/supervisord.conf

###############################
# 启动 supervisord 作为容器入口进程
###############################


CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
