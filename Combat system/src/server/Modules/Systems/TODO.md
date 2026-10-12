PRIORIDADE (a questão do movimento ao atacar, que foi a última modificação):
1. Restaurar --!strict em CombatUtil.
2. Corrigir os loops de attacks com pairs().
3. Corrigir os acessos usando as chaves player e attackId.
4. Substituir os índices values[1], values[2] etc. por campos nomeados.
5. Usar GetPartBoundsInBox() para os socos.
6. Recalcular o CFrame da hitbox durante a janela ativa.
7. Registrar os humanoides atingidos para impedir dano repetido.
8. Aplicar o limite de alvos por golpe.
9. Criar um debug por ataque, com tamanho e posição iguais aos da consulta.
10. Encerrar e limpar ataques ao expirar, parar a animação, cancelar ou remover o personagem.
11. Mover tamanho, deslocamento, duração e limite de alvos para as configurações dos golpes do estilo.
12. Revalidar personagem, estado e cooldown após esperar a animação carregar.
13. Testar movimento, rotação, múltiplos jogadores, cancelamento e respawn.

TAREFAS
fazer com que o jogador sejá impossibilitado de pular ao atacar ou ser atacado. Acho que na verdade qualquer estado vai fazer isso..

dash system: 
lateral dash,
front dash, 
back dash, 
baseado em wasd, 
lembrando de estados, cooldown, e aplicar animação apropriada

uppercut e downcut
espaço + click, respeitando respeito: uppercut
espaço, click caindo, respeitando respeito: downcut

npcs que bloqueiam e atacam + gui para spawnar eles

habilidades:
1234 soltam habilidades
esqueleto já está pronto, tem que catar animações e ver como fazer

quando terminar tudo, revisar todos os códigos, pedir análise de IA, aprenda mais ainda
com o que você já aprendeu, testa bastante e otimiza tudo, pedir pra IA colocar tipagem
