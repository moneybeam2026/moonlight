import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Param,
  Body,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { UsersService, User } from './users.service';

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get()
  getAllUsers(): User[] {
    return this.usersService.findAll();
  }

  @Get(':id')
  getUserById(@Param('id') id: string): User {
    const user = this.usersService.findOne(Number(id));
    if (!user) {
      throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    }
    return user;
  }

  @Post()
  createUser(
    @Body()
    userData: {
      firstName: string;
      lastName: string;
      email: string;
      age: number;
      city: string;
    },
  ): User {
    return this.usersService.create(userData);
  }

  @Put(':id')
  updateUser(
    @Param('id') id: string,
    @Body()
    userData: {
      firstName?: string;
      lastName?: string;
      email?: string;
      age?: number;
      city?: string;
    },
  ): User {
    const user = this.usersService.update(Number(id), userData);
    if (!user) {
      throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    }
    return user;
  }

  @Delete(':id')
  deleteUser(@Param('id') id: string): { message: string } {
    const deleted = this.usersService.delete(Number(id));
    if (!deleted) {
      throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    }
    return { message: 'User deleted successfully' };
  }
}
