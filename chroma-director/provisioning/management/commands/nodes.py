
from provisioning.models import ChromaManager, ChromaAppliance, Node

import settings
from django.core.management.base import BaseCommand
from boto.ec2.connection import EC2Connection

from fabric.operations import open_shell

from provisioning.lib.chroma_ops import NodeOps

import time

class Command(BaseCommand):
    args = "list|ssh <id>|terminate all"
    help = "Utility command to manage instances"
    can_import_settings = True

    def handle(self, *args, **options):
        if not args or args[0] == 'list':
            for n in Node.objects.all():
                i = n.get_instance()
                print n.id, n.ec2_id, n.name, i.state, i.ip_address

        elif args[0] == 'terminate' and args[1] == 'all':
#            conn = EC2Connection(settings.AWS_KEY_ID, settings.AWS_SECRET)
            for node in Node.objects.all():
                node_ops = NodeOps(node);
                node.terminate(node)
#            conn.terminate_instances([i.ec2_id for i in Node.objects.all()])
#            Node.objects.all().delete()

        elif args[0] == 'terminate' and int(args[1]) > 0:
            node_id = int(args[1])
            node = Node.objects.get(id = node_id)
            node_ops = NodeOps(node)
            node_ops.terminate()

        elif args[0] == 'ssh':
            node_id = int(args[1])
            node = Node.objects.get(id = node_id)
            session = node.get_session()
            import os
            SSH_BIN = "/usr/bin/ssh"
            os.execvp(SSH_BIN, ["ssh", "-i", settings.AWS_SSH_PRIVATE_KEY, 
                                "%s@%s" % (node.username, session.instance.ip_address)])

            
                
                
